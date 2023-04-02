// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "./VeOil.sol";

/// @title Vote Escrow Oil Staking
/// @notice Stake Oil to earn veOil, which you can use to earn higher farm yields and gain
/// voting power. Note that unstaking any amount of Oil will burn all of your existing veOil.
contract VeOilStaking is  OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Info for each user
    /// `balance`: Amount of Oil currently staked by user
    /// `rewardDebt`: The reward debt of the user
    /// `lastClaimTimestamp`: The timestamp of user's last claim or withdraw
    /// `speedUpEndTimestamp`: The timestamp when user stops receiving speed up benefits, or
    /// zero if user is not currently receiving speed up benefits
    struct UserInfo {
        uint256 balance;
        uint256 rewardDebt;
        uint256 lastClaimTimestamp;
        uint256 speedUpEndTimestamp;
        /**
         * @notice We do some fancy math here. Basically, any point in time, the amount of veOil
         * entitled to a user but is pending to be distributed is:
         *
         *   pendingReward = pendingBaseReward + pendingSpeedUpReward
         *
         *   pendingBaseReward = (user.balance * accVeOilPerShare) - user.rewardDebt
         *
         *   if user.speedUpEndTimestamp != 0:
         *     speedUpCeilingTimestamp = min(block.timestamp, user.speedUpEndTimestamp)
         *     speedUpSecondsElapsed = speedUpCeilingTimestamp - user.lastClaimTimestamp
         *     pendingSpeedUpReward = speedUpSecondsElapsed * user.balance * speedUpVeOilPerSharePerSec
         *   else:
         *     pendingSpeedUpReward = 0
         */
    }

    IERC20 public oil;
    VeOil public veOil;

    /// @notice The maximum limit of veOil user can have as percentage points of staked Oil
    /// For example, if user has `n` Oil staked, they can own a maximum of `n * maxCapPct / 100` veOil.
    uint256 public maxCapPct;

    /// @notice The upper limit of `maxCapPct`
    uint256 public upperLimitMaxCapPct;

    /// @notice The accrued veOil per share, scaled to `ACC_VEOIL_PER_SHARE_PRECISION`
    uint256 public accVeOilPerShare;

    /// @notice Precision of `accVeOilPerShare`
    uint256 public ACC_VEOIL_PER_SHARE_PRECISION;

    /// @notice The last time that the reward variables were updated
    uint256 public lastRewardTimestamp;

    /// @notice veOil per sec per Oil staked, scaled to `VEOIL_PER_SHARE_PER_SEC_PRECISION`
    uint256 public veOilPerSharePerSec;

    /// @notice Speed up veOil per sec per Oil staked, scaled to `VEOIL_PER_SHARE_PER_SEC_PRECISION`
    uint256 public speedUpVeOilPerSharePerSec;

    /// @notice The upper limit of `veOilPerSharePerSec` and `speedUpVeOilPerSharePerSec`
    uint256 public upperLimitVeOilPerSharePerSec;

    /// @notice Precision of `veOilPerSharePerSec`
    uint256 public VEOIL_PER_SHARE_PER_SEC_PRECISION;

    /// @notice Percentage of user's current staked Oil user has to deposit in order to start
    /// receiving speed up benefits, in parts per 100.
    /// @dev Specifically, user has to deposit at least `speedUpThreshold/100 * userStakedOil` Oil.
    /// The only exception is the user will also receive speed up benefits if they are depositing
    /// with zero balance
    uint256 public speedUpThreshold;

    /// @notice The length of time a user receives speed up benefits
    uint256 public speedUpDuration;

    mapping(address => UserInfo) public userInfos;

    event Claim(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);
    event UpdateMaxCapPct(address indexed user, uint256 maxCapPct);
    event UpdateRewardVars(uint256 lastRewardTimestamp, uint256 accVeOilPerShare);
    event UpdateSpeedUpThreshold(address indexed user, uint256 speedUpThreshold);
    event UpdateVeOilPerSharePerSec(address indexed user, uint256 veOilPerSharePerSec);
    event Withdraw(address indexed user, uint256 withdrawAmount, uint256 burnAmount);

    /// @notice Initialize with needed parameters
    /// @param _oil Address of the Oil token contract
    /// @param _veOil Address of the veOil token contract
    function initialize(
        IERC20 _oil,
        VeOil _veOil
    ) public initializer {
        __Ownable_init();

        require(address(_oil) != address(0), "VeOilStaking: unexpected zero address for _oil");
        require(address(_veOil) != address(0), "VeOilStaking: unexpected zero address for _veOil");

        upperLimitVeOilPerSharePerSec = 1e36;
        upperLimitMaxCapPct = 10000000;

        maxCapPct = 10000;
        speedUpThreshold = 5;
        speedUpDuration = 15 days;
        oil = _oil;
        veOil = _veOil;
        uint256 temp = 100 ether;
        veOilPerSharePerSec = temp / 365 days;
        speedUpVeOilPerSharePerSec = veOilPerSharePerSec;
        lastRewardTimestamp = block.timestamp;
        ACC_VEOIL_PER_SHARE_PRECISION = 1e18;
        VEOIL_PER_SHARE_PER_SEC_PRECISION = 1e18;
    }

    /// @notice Set maxCapPct
    /// @param _maxCapPct The new maxCapPct
    function setMaxCapPct(uint256 _maxCapPct) external onlyOwner {
        require(_maxCapPct > maxCapPct, "VeOilStaking: expected new _maxCapPct to be greater than existing maxCapPct");
        require(
            _maxCapPct != 0 && _maxCapPct <= upperLimitMaxCapPct,
            "VeOilStaking: expected new _maxCapPct to be non-zero and <= 10000000"
        );
        maxCapPct = _maxCapPct;
        emit UpdateMaxCapPct(_msgSender(), _maxCapPct);
    }

    /// @notice Set veOilPerSharePerSec
    /// @param _veOilPerSharePerSec The new veOilPerSharePerSec
    function setVeOilPerSharePerSec(uint256 _veOilPerSharePerSec) external onlyOwner {
        require(
            _veOilPerSharePerSec <= upperLimitVeOilPerSharePerSec,
            "VeOilStaking: expected _veOilPerSharePerSec to be <= 1e36"
        );
        updateRewardVars();
        veOilPerSharePerSec = _veOilPerSharePerSec;
        emit UpdateVeOilPerSharePerSec(_msgSender(), _veOilPerSharePerSec);
    }

    /// @notice Set speedUpThreshold
    /// @param _speedUpThreshold The new speedUpThreshold
    function setSpeedUpThreshold(uint256 _speedUpThreshold) external onlyOwner {
        require(
            _speedUpThreshold != 0 && _speedUpThreshold <= 100,
            "VeOilStaking: expected _speedUpThreshold to be > 0 and <= 100"
        );
        speedUpThreshold = _speedUpThreshold;
        emit UpdateSpeedUpThreshold(_msgSender(), _speedUpThreshold);
    }

    /// @notice Deposits Oil to start staking for veOil. Note that any pending veOil
    /// will also be claimed in the process.
    /// @param _amount The amount of Oil to deposit
    function deposit(uint256 _amount) external {
        require(_amount > 0, "VeOilStaking: expected deposit amount to be greater than zero");

        updateRewardVars();

        UserInfo storage userInfo = userInfos[_msgSender()];

        if (_getUserHasNonZeroBalance(_msgSender())) {
            // Transfer to the user their pending veOil before updating their UserInfo
            _claim();

            // We need to update user's `lastClaimTimestamp` to now to prevent
            // passive veOil accrual if user hit their max cap.
            userInfo.lastClaimTimestamp = block.timestamp;

            uint256 userStakedOil = userInfo.balance;

            // User is eligible for speed up benefits if `_amount` is at least
            // `speedUpThreshold / 100 * userStakedOil`
            if (_amount.mul(100) >= speedUpThreshold.mul(userStakedOil)) {
                userInfo.speedUpEndTimestamp = block.timestamp.add(speedUpDuration);
            }
        } else {
            // If user is depositing with zero balance, they will automatically
            // receive speed up benefits
            userInfo.speedUpEndTimestamp = block.timestamp.add(speedUpDuration);
            userInfo.lastClaimTimestamp = block.timestamp;
        }

        userInfo.balance = userInfo.balance.add(_amount);
        userInfo.rewardDebt = accVeOilPerShare.mul(userInfo.balance).div(ACC_VEOIL_PER_SHARE_PRECISION);

        oil.safeTransferFrom(_msgSender(), address(this), _amount);

        emit Deposit(_msgSender(), _amount);
    }

    /// @notice Withdraw staked Oil. Note that unstaking any amount of Oil means you will
    /// lose all of your current veOil.
    /// @param _amount The amount of Oil to unstake
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "VeOilStaking: expected withdraw amount to be greater than zero");

        UserInfo storage userInfo = userInfos[_msgSender()];

        require(
            userInfo.balance >= _amount,
            "VeOilStaking: cannot withdraw greater amount of Oil than currently staked"
        );
        updateRewardVars();

        // Note that we don't need to claim as the user's veOil balance will be reset to 0
        userInfo.balance = userInfo.balance.sub(_amount);
        userInfo.rewardDebt = accVeOilPerShare.mul(userInfo.balance).div(ACC_VEOIL_PER_SHARE_PRECISION);
        userInfo.lastClaimTimestamp = block.timestamp;
        userInfo.speedUpEndTimestamp = 0;

        // Burn the user's current veOil balance
        uint256 userVeOilBalance = veOil.balanceOf(_msgSender());
        veOil.burnFrom(_msgSender(), userVeOilBalance);

        // Send user their requested amount of staked Oil
        oil.safeTransfer(_msgSender(), _amount);

        emit Withdraw(_msgSender(), _amount, userVeOilBalance);
    }

    /// @notice Claim any pending veOil
    function claim() external {
        require(_getUserHasNonZeroBalance(_msgSender()), "VeOilStaking: cannot claim veOil when no Oil is staked");
        updateRewardVars();
        _claim();
    }

    /// @notice Get the pending amount of veOil for a given user
    /// @param _user The user to lookup
    /// @return The number of pending veOil tokens for `_user`
    function getPendingVeOil(address _user) public view returns (uint256) {
        if (!_getUserHasNonZeroBalance(_user)) {
            return 0;
        }

        UserInfo memory user = userInfos[_user];

        // Calculate amount of pending base veOil
        uint256 _accVeOilPerShare = accVeOilPerShare;
        uint256 secondsElapsed = block.timestamp.sub(lastRewardTimestamp);
        if (secondsElapsed > 0) {
            _accVeOilPerShare = _accVeOilPerShare.add(
                secondsElapsed.mul(veOilPerSharePerSec).mul(ACC_VEOIL_PER_SHARE_PRECISION).div(
                    VEOIL_PER_SHARE_PER_SEC_PRECISION
                )
            );
        }
        uint256 pendingBaseVeOil = _accVeOilPerShare.mul(user.balance).div(ACC_VEOIL_PER_SHARE_PRECISION).sub(
            user.rewardDebt
        );

        // Calculate amount of pending speed up veOil
        uint256 pendingSpeedUpVeOil;
        if (user.speedUpEndTimestamp != 0) {
            uint256 speedUpCeilingTimestamp = block.timestamp > user.speedUpEndTimestamp
                ? user.speedUpEndTimestamp
                : block.timestamp;
            uint256 speedUpSecondsElapsed = speedUpCeilingTimestamp.sub(user.lastClaimTimestamp);
            uint256 speedUpAccVeOilPerShare = speedUpSecondsElapsed.mul(speedUpVeOilPerSharePerSec);
            pendingSpeedUpVeOil = speedUpAccVeOilPerShare.mul(user.balance).div(VEOIL_PER_SHARE_PER_SEC_PRECISION);
        }

        uint256 pendingVeOil = pendingBaseVeOil.add(pendingSpeedUpVeOil);

        // Get the user's current veOil balance
        uint256 userVeOilBalance = veOil.balanceOf(_user);

        // This is the user's max veOil cap multiplied by 100
        uint256 scaledUserMaxVeOilCap = user.balance.mul(maxCapPct);

        if (userVeOilBalance.mul(100) >= scaledUserMaxVeOilCap) {
            // User already holds maximum amount of veOil so there is no pending veOil
            return 0;
        } else if (userVeOilBalance.add(pendingVeOil).mul(100) > scaledUserMaxVeOilCap) {
            return scaledUserMaxVeOilCap.sub(userVeOilBalance.mul(100)).div(100);
        } else {
            return pendingVeOil;
        }
    }

    /// @notice Update reward variables
    function updateRewardVars() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if (oil.balanceOf(address(this)) == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 secondsElapsed = block.timestamp.sub(lastRewardTimestamp);
        accVeOilPerShare = accVeOilPerShare.add(
            secondsElapsed.mul(veOilPerSharePerSec).mul(ACC_VEOIL_PER_SHARE_PRECISION).div(
                VEOIL_PER_SHARE_PER_SEC_PRECISION
            )
        );
        lastRewardTimestamp = block.timestamp;

        emit UpdateRewardVars(lastRewardTimestamp, accVeOilPerShare);
    }

    function veOilStakingInfo(address _user) public view returns (
        uint256 totalStakingOilAmount_,
        uint256 veOilTotalSupply_,
        uint256 maxCapPct_,
        uint256 speedUpThreshold_,
        uint256 speedUpDuration_,
        uint256 stakingOilAmount_,
        uint256 pendingVeOilAmount_,
        uint256 balanceOfOil_,
        uint256 balanceOfVeOil_,
        uint256 speedUpEndTimestamp_,
        uint256 veOilRewardPerDay_ 
    ){
        totalStakingOilAmount_ = oil.balanceOf(address(this));
        veOilTotalSupply_ = veOil.totalSupply();
        maxCapPct_ = maxCapPct;
        speedUpThreshold_ = speedUpThreshold;
        speedUpDuration_ = speedUpDuration;
        if (_user != address(0)) {
            UserInfo memory userInfo = userInfos[_user];
            stakingOilAmount_ = userInfo.balance;
            pendingVeOilAmount_ = getPendingVeOil(_user);
            balanceOfOil_ = oil.balanceOf(_user);
            balanceOfVeOil_ = veOil.balanceOf(_user);
            speedUpEndTimestamp_ = userInfo.speedUpEndTimestamp;
            uint256 veOilPerSec = veOilPerSharePerSec + ((speedUpEndTimestamp_ > block.timestamp) ? speedUpVeOilPerSharePerSec : 0);
            veOilRewardPerDay_ = veOilPerSec * 24 * 3600 * stakingOilAmount_ / 1e18;
        }
    }

    /// @notice Checks to see if a given user currently has staked Oil
    /// @param _user The user address to check
    /// @return Whether `_user` currently has staked Oil
    function _getUserHasNonZeroBalance(address _user) private view returns (bool) {
        return userInfos[_user].balance > 0;
    }

    /// @dev Helper to claim any pending veOil
    function _claim() private {
        uint256 veOilToClaim = getPendingVeOil(_msgSender());

        UserInfo storage userInfo = userInfos[_msgSender()];

        userInfo.rewardDebt = accVeOilPerShare.mul(userInfo.balance).div(ACC_VEOIL_PER_SHARE_PRECISION);

        // If user's speed up period has ended, reset `speedUpEndTimestamp` to 0
        if (userInfo.speedUpEndTimestamp != 0 && block.timestamp >= userInfo.speedUpEndTimestamp) {
            userInfo.speedUpEndTimestamp = 0;
        }

        if (veOilToClaim > 0) {
            userInfo.lastClaimTimestamp = block.timestamp;

            veOil.mint(_msgSender(), veOilToClaim);
            emit Claim(_msgSender(), veOilToClaim);
        }
    }
}