// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../library/SafeERC20.sol";
import "../interfaces/IPriceCalculator.sol";
import "../interfaces/ICapacityPackage.sol";
import "../interfaces/IMinePool.sol";
import "../interfaces/ITreasury.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IFarm {
    function farmInfo() external view returns(address stakingToken_, address earnedToken_, uint256 totalStakingAmount_, uint256 maxRewardAmount_, uint256 totalRewardAmount_, uint256 dailyReward_);
    function userInfo(address _user) external view returns(uint256 stakingAmount_, uint256 pendingOil_);
}


contract Dashboard is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public payToken;
    address public oil;
    IPriceCalculator public priceCalculator;
    ICapacityPackage public capacityPackage;
    IMinePool public minePool;
    ITreasury public treasury;

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public lpFarm;

    function initialize(
        address _payToken,
        address _oil,
        address _priceCalculator,
        address _capacityPackage,
        address _minePool,
        address _treasury
    ) external initializer {
        require(_payToken != address(0));
        require(_oil != address(0));
        require(_priceCalculator != address(0));
        require(_capacityPackage != address(0));
        require(_minePool != address(0));
        require(_treasury != address(0));

        __Ownable_init();

        payToken = _payToken;
        oil = _oil;
        priceCalculator = IPriceCalculator(_priceCalculator);
        capacityPackage = ICapacityPackage(_capacityPackage);
        minePool = IMinePool(_minePool);
        treasury = ITreasury(_treasury);
    }

    function setLpFarm(address _lpFarm) public onlyOwner {
        require(_lpFarm != address(0));
        lpFarm = _lpFarm;
    }

    function totalMineInfo() public view returns(
        uint8   k_,
        bool    addition_,
        uint32  claimCD_,
        uint32  basePct_,
        uint256 oilPerSec_,
        IMinePool.PoolOilInfo[3] memory info_
    ) {
        return minePool.totalMineInfo();
    }

    function tokenInfo(address _account) public view returns(
        uint256 priceOfOil_,
        uint256 balaceOfPayToken_,
        uint256 balanceOfOil_,
        uint256 balanceOfCapacity_,
        uint256 burnAmountOfOil_
    ) {
        priceOfOil_ = priceCalculator.priceOfToken(oil);
        if (_account != address(0)) {
            if (treasury.isNativeToken(payToken)) {
                balaceOfPayToken_ = _account.balance;
            } else {
                balaceOfPayToken_ = IERC20(payToken).balanceOf(_account);
            }
            balanceOfOil_ = IERC20(oil).balanceOf(_account);
            balanceOfCapacity_ = capacityPackage.userCapacityPacakage(_account);
        } else {
            balaceOfPayToken_ = 0;
            balanceOfOil_ = 0;
            balanceOfCapacity_ = 0;
        }
        burnAmountOfOil_ = IERC20(oil).balanceOf(DEAD);
    }

    function getOilAmount(uint256 _payTokenAmt) public view returns(uint256) {
        (, uint256 OilAmt) = treasury.getAmount(1, _payTokenAmt);
        return OilAmt;
    }

    function lpFarmInfo(address _user) public view returns(
        uint256 tvl,
        uint256 totalStakingAmount,
        uint256 dapr,
        uint256 stakingAmount, 
        uint256 pendingOil
    ) {
        (address stakingToken_, address earnedToken_, uint256 totalStakingAmount_,,,uint256 dailyReward_) = IFarm(lpFarm).farmInfo();
        uint256 stakingPrice = priceOfToken(stakingToken_);
        tvl = totalStakingAmount_.mul(stakingPrice).div(1e18);
        totalStakingAmount = totalStakingAmount_;
        uint256 earnedPrice = priceOfToken(earnedToken_);
        if (tvl > 0) {
            dapr = dailyReward_.mul(earnedPrice).div(tvl);
        }
        if (_user != address(0)) {
            (stakingAmount, pendingOil) = IFarm(lpFarm).userInfo(_user);
        }
    }

    function priceOfToken(address _token) public view returns(uint256) {
        return priceCalculator.priceOfToken(_token);
    }
}