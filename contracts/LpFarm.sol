// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "./interfaces/IERC721Enumerable.sol";
import "./interfaces/IOil.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract LpFarm is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 shares;
        uint256 pending; 
        uint256 rewardPaid;
    }

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event WithdrawAll(address indexed user, uint256 amount, uint256 earnedOil);
    event ClaimOil(address indexed user, uint256 earnedOil);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    address public oil;
    address public stakingToken;

    uint256 public oilPerSec;
    uint256 public lastRewardTimestamp;
    uint256 public accPerShare;
    uint256 public MAX_REWARD_AMOUNT;
    uint256 public totalRewardAmount;

    mapping (address=>UserInfo) public users;


    function initialize(
        address _oil,
        address _stakingToken,
        uint256 _startTimestamp
    ) external initializer {
        require(_oil != address(0), "Invalid oil");
        require(_stakingToken != address(0), "Invalid stakingToken");

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        oil = _oil;
        stakingToken = _stakingToken;
        lastRewardTimestamp = (_startTimestamp > 0) ? _startTimestamp : block.timestamp;
        oilPerSec = 42 ether;
        accPerShare = 0;
        MAX_REWARD_AMOUNT = 5000000000 ether;
        totalRewardAmount = 0;
    }

    function setOilPerSec(uint256 _perSec) external onlyOwner {
        updatePool();
        oilPerSec = _perSec;
    }

    function setMaxRewardAmount(uint256 _maxRewardAmount) external onlyOwner {
        MAX_REWARD_AMOUNT = _maxRewardAmount;
        updatePool();
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function farmInfo() public view returns(address stakingToken_, address earnedToken_, uint256 totalStakingAmount_, uint256 maxRewardAmount_, uint256 totalRewardAmount_, uint256 dailyReward_) {
        stakingToken_ = stakingToken;
        earnedToken_ = oil;
        totalStakingAmount_ = IERC20(stakingToken_).balanceOf(address(this));
        (maxRewardAmount_, totalRewardAmount_) = rewardAmountInfo();
        dailyReward_ = oilPerSec * 86400;
    }

    function userInfo(address _user) public view returns(uint256 stakingAmount_, uint256 pendingOil_) {
        UserInfo memory user = users[_user];
        stakingAmount_ = user.shares;
        pendingOil_ = pendingOil(_user);
    }

    function pendingOil(address _user) public view returns (uint256) {
        UserInfo memory user = users[_user];
        uint256 supply = IERC20(stakingToken).balanceOf(address(this));
        uint256 tempAccPerShare = accPerShare;
        if (block.timestamp > lastRewardTimestamp && supply != 0) {
            uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 oilReward = multiplier.mul(oilPerSec);
            if (totalRewardAmount + oilReward > MAX_REWARD_AMOUNT) {
                oilReward = MAX_REWARD_AMOUNT - totalRewardAmount;
            }
            tempAccPerShare = tempAccPerShare.add(oilReward.mul(1e12).div(supply));
        }

        uint256 pending = user.pending.add(user.shares.mul(tempAccPerShare).div(1e12).sub(user.rewardPaid));
        return pending;
    }

    function rewardAmountInfo() public view returns(uint256 maxRewardAmount_, uint256 totalRewardAmount_) {
        maxRewardAmount_ = MAX_REWARD_AMOUNT;
        totalRewardAmount_ = totalRewardAmount;
        if (block.timestamp > lastRewardTimestamp) {
            uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 oilReward = multiplier.mul(oilPerSec);
            totalRewardAmount_ += oilReward;
            if (totalRewardAmount_ > maxRewardAmount_) {
                totalRewardAmount_ = maxRewardAmount_;
            }
        }
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if (totalRewardAmount >= MAX_REWARD_AMOUNT) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 supply = IERC20(stakingToken).balanceOf(address(this));
        if (supply <= 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
        uint256 oilReward = multiplier.mul(oilPerSec);
        if (totalRewardAmount + oilReward > MAX_REWARD_AMOUNT) {
            oilReward = MAX_REWARD_AMOUNT - totalRewardAmount;
        }
        accPerShare = accPerShare.add(oilReward.mul(1e12).div(supply));
        totalRewardAmount += oilReward;
        lastRewardTimestamp = block.timestamp;
    }

    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function deposit(uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount > 0, "_amount == 0");
        updatePool();

        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), _amount);
        UserInfo storage user = users[msg.sender];
        uint256 pending = user.shares.mul(accPerShare).div(1e12).sub(user.rewardPaid);
        user.pending = user.pending.add(pending);
        user.shares = user.shares.add(_amount);
        user.rewardPaid = user.shares.mul(accPerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, "_amount == 0");

        UserInfo storage user = users[msg.sender];
        require(user.shares >= _amount, "user shares < amount");

        updatePool();
        uint256 pending = user.shares.mul(accPerShare).div(1e12).sub(user.rewardPaid);
        user.pending = user.pending.add(pending);
        user.shares = user.shares.sub(_amount);
        user.rewardPaid = user.shares.mul(accPerShare).div(1e12);

        IERC20(stakingToken).safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
    }

    function withdrawAll() external nonReentrant {
        UserInfo memory user = users[msg.sender];
        require(user.shares > 0, "user shares == 0");

        updatePool();
        IERC20(stakingToken).safeTransfer(msg.sender, user.shares);

        uint256 pending = user.shares.mul(accPerShare).div(1e12).sub(user.rewardPaid);
        uint256 earnedOil = user.pending.add(pending);
        IOil(oil).mint(msg.sender, earnedOil);

        delete users[msg.sender];
        emit WithdrawAll(msg.sender, user.shares, earnedOil);
    }

    function claimOil() external whenNotPaused nonReentrant {
        updatePool();
        UserInfo storage user = users[msg.sender];
        uint256 pending = user.shares.mul(accPerShare).div(1e12).sub(user.rewardPaid);
        uint256 earnedOil = user.pending.add(pending);
        user.pending = 0;
        user.rewardPaid = user.shares.mul(accPerShare).div(1e12);
        IOil(oil).mint(msg.sender, earnedOil);
        emit ClaimOil(msg.sender, earnedOil);
    }

    function emergencyWithdraw() public nonReentrant {
        UserInfo memory user = users[msg.sender];
        require(user.shares > 0, "user shares == 0");
        IERC20(stakingToken).safeTransfer(msg.sender, user.shares);
        delete users[msg.sender];
        emit EmergencyWithdraw(msg.sender, user.shares);
    }

    function withdrawBEP20(address _tokenAddress, address _to, uint256 _amount) public onlyOwner {
        require(_tokenAddress != oil && _tokenAddress != stakingToken);
        uint256 tokenBal = IERC20(_tokenAddress).balanceOf(address(this));
        if (_amount == 0 || _amount >= tokenBal) {
            _amount = tokenBal;
        }
        IERC20(_tokenAddress).transfer(_to, _amount);
    }
}