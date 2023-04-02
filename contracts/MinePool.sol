// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "./interfaces/IWellEnumerable.sol";
import "./interfaces/IMineEnumerable.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IMinePool.sol";
import "./interfaces/IOil.sol";
import "./interfaces/IFriends.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract MinePool is IMinePool, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event StartMine(address indexed account, uint32 mineId, uint32 wellId);
    event AddCapacity(uint32 mineId, uint256 capacity);
    event Claim(address indexed account, uint32 mineId, uint256 rewards);
    event WithdrawWell(address indexed account, uint32 mineId, uint32 wellId);

    struct MineInfo {
        uint32[] wells;
        uint256 power;
        uint256 capacity;
        uint256 shares;
        uint256 pending;
        uint256 rewardPaid;
        uint256 lastClaimTime;
    }

    struct PoolInfo {
        uint8 cid;
        uint256 basePct;
        uint256 dynamicPct;
        uint256 sharesTotal;
        uint256 totalCapacity;
        uint256 accPerShare;
    }

    IWellEnumerable public well;
    IMineEnumerable public mine;
    ITreasury public treasury;
    address public oil;
    uint32 public claimCD;
    mapping(address => bool) public authControllers;
    address public controller;
    mapping(uint32 => MineInfo) public mines;

    uint256 public startTimestamp;
    uint256 public oilPerSec;
    uint256 public minOilPerSec;
    uint256 public lastRewardTimestamp;
    uint256 public halvingCycle;
    uint256 public latestHalvingTimestamp;
    uint256 public MAX_REWARD_AMOUNT;
    uint256 public totalRewardAmount;
    uint256 public unitPower;
    uint8 public K;
    bool public addition;
    IFriends public friends;
    address public pairToken;
    uint256 public totalClaimRewardAmount;
    PoolInfo[] public poolInfo;
    uint32 public basePct;

    function initialize(
        address _well,
        address _mine,
        address _treasury,
        address _oil,
        address _pairToken
    ) external initializer {
        require(_well != address(0));
        require(_mine != address(0));
        require(_treasury != address(0));
        require(_oil != address(0));
        require(_pairToken != address(0));

        __Ownable_init();
        __Pausable_init();

        well = IWellEnumerable(_well);
        mine = IMineEnumerable(_mine);
        treasury = ITreasury(_treasury);
        oil = _oil;
        pairToken = _pairToken;
        controller = msg.sender;

        claimCD = 1 days;
        oilPerSec = 512 * 1e18;
        minOilPerSec = 1e18;
        halvingCycle = 90 days;
        MAX_REWARD_AMOUNT = 14950000000 * 1e18;
        unitPower = 100;
        K = 0;
        addition = true;

        PoolInfo memory info1;
        info1.cid = 1;
        info1.basePct = 1;
        poolInfo.push(info1);

        PoolInfo memory info2;
        info2.cid = 2;
        info2.basePct = 2;
        poolInfo.push(info2);

        PoolInfo memory info3;
        info3.cid = 3;
        info3.basePct = 4;
        poolInfo.push(info3);

        basePct = 20;
    }

    function setAuthControllers(address _contracts, bool _enable) external onlyOwner {
        authControllers[_contracts] = _enable;
    }

    function setController(address _controller) external onlyOwner returns ( bool ) {
        controller = _controller;
        return true;
    }

    function setMine(address _mine) external onlyOwner {
        require(_mine != address(0));
        mine = IMineEnumerable(_mine);
    }

    modifier onlyController() {
        require(controller == msg.sender, "Caller is not the controller");
        _;
    }

    function setClaimCD(uint32 _cd) external onlyOwner {
        claimCD = _cd;
    }

    function setOilPerSec(uint256 _perSec) external onlyController {
        _updatePool();
        oilPerSec = _perSec;
    }

    function setMinOilPerSec(uint256 _perSec) external onlyController {
        minOilPerSec = _perSec;
    }

    function setHalvingCycle(uint256 _secs) external onlyController {
        halvingCycle = _secs;
    }

    function setK(uint8 _k, bool _addition) external onlyController {
        require(_k <= 30);
        _updatePool();
        K = _k;
        addition = _addition;
    }


    function setBasePct(uint256[] memory _pct) external onlyController {
        _updatePool();
        for (uint256 i = 0; i < _pct.length; ++i) {
            poolInfo[i].basePct = _pct[i];
        }
    }

    function setMAX_REWARD_AMOUNT(uint256 _amount) external onlyOwner {
        MAX_REWARD_AMOUNT = _amount * 1e18;
    }

    function setFriends(address _friends) external onlyOwner {
        require(_friends != address(0));
        friends = IFriends(_friends);
    }

    function setBasePct(uint32 _pct) external onlyOwner {
        _updatePool();
        basePct = _pct;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function launch(uint256 _time) external onlyOwner {
        require(startTimestamp == 0, "Already launched");
        startTimestamp = (_time <= block.timestamp) ? block.timestamp : _time;
        latestHalvingTimestamp = startTimestamp;

        uint256[3] memory capacity = mine.eachTypeG0Capacity();
        _adjustDynamicPct(capacity);
    }

    function voteDynamicPct(uint256[3] memory _dynamicPct) external override onlyController {
        _updatePool();
        _adjustDynamicPct(_dynamicPct);
    }

    function _adjustDynamicPct(uint256[3] memory _dynamicPct) private {
        for (uint8 i = 0; i < 3; ++i) {
            poolInfo[i].dynamicPct = _dynamicPct[i];
        }
    }

    function startMine(uint32 _mineId, uint32 _wellId) external whenNotPaused {
        require(startTimestamp > 0, "Not start");
        require(tx.origin == _msgSender(), "Not EOA");
        require(mine.ownerOf(_mineId) == msg.sender, "Not owner");
        require(well.ownerOf(_wellId) == msg.sender, "Not owner");
        _updatePool();

        MineInfo memory info = mines[_mineId];
        require(info.wells.length == 0, "Well already exists");
        require(info.capacity == 0, "capacity > 0");
        well.transferFrom(_msgSender(), address(this), _wellId);

        IWell.sWell memory w = well.getTokenTraits(_wellId);
        IMine.sMine memory m = mine.getTokenTraits(_mineId);
        PoolInfo memory pInfo = poolInfo[m.cid - 1];
        info.power += w.speedBuf * m.speedBuf / 100;
        uint256 amount = m.capacity;
        uint256 addShares = amount.mul(info.power).div(100);
        uint256 pending = info.shares.mul(pInfo.accPerShare).div(1e12).sub(info.rewardPaid);
        info.pending = info.pending.add(pending);
        info.capacity = info.capacity.add(amount);
        info.shares = info.shares.add(addShares);
        info.rewardPaid = info.shares.mul(pInfo.accPerShare).div(1e12);
        if (info.lastClaimTime == 0) {
            info.lastClaimTime = uint32(block.timestamp);
        }
        mines[_mineId] = info;
        mines[_mineId].wells.push(_wellId);

        pInfo.totalCapacity = pInfo.totalCapacity.add(amount);
        pInfo.sharesTotal = pInfo.sharesTotal.add(addShares);
        poolInfo[m.cid - 1] = pInfo;
        emit StartMine(msg.sender, _mineId, _wellId);
    }

    function claim(uint32 _mineId) external whenNotPaused {
        require(startTimestamp > 0, "Not start");
        require(tx.origin == _msgSender(), "Not EOA");
        require(mine.ownerOf(_mineId) == msg.sender, "Not owner");
        MineInfo memory info = mines[_mineId];
        require(info.wells.length > 0, "Not working");
        require(block.timestamp >= info.lastClaimTime + claimCD, "Countdown");
        _updatePool();

        IMine.sMine memory m = mine.getTokenTraits(_mineId);
        PoolInfo memory pInfo = poolInfo[m.cid - 1];
        uint256 pending = info.shares.mul(pInfo.accPerShare).div(1e12).sub(info.rewardPaid);
        uint256 earned = info.pending.add(pending);
        info.pending = 0;
        if (earned > 0) {
            address pair = IOil(oil).pair();
            uint256 amount = treasury.getAmountOut(pair, oil, earned);
            if (amount > info.capacity) {
                amount = info.capacity;
                earned = treasury.getAmountOut(pair, pairToken, amount);
            }
            info.capacity = info.capacity.sub(amount);
            uint256 subShares = amount.mul(info.power).div(100);
            info.shares = info.shares.sub(subShares);
            pInfo.totalCapacity = pInfo.totalCapacity.sub(amount);
            pInfo.sharesTotal = pInfo.sharesTotal.sub(subShares);

            m.capacity = m.capacity.sub(amount);
            m.cumulativeOutput = m.cumulativeOutput.add(amount);
            mine.updateTokenTraits(m);
            IOil(oil).mint(msg.sender, earned);
        }
        info.rewardPaid = info.shares.mul(pInfo.accPerShare).div(1e12);
        info.lastClaimTime = uint32(block.timestamp);
        mines[_mineId] = info;
        totalClaimRewardAmount = totalClaimRewardAmount.add(earned);
        friends.clearUp(_mineId);
        poolInfo[m.cid - 1] = pInfo;
        emit Claim(msg.sender, _mineId, earned);
    }

    function withdrawWell(uint32 _mineId, uint32 _wellId) external {
        require(tx.origin == _msgSender(), "Not EOA");
        require(mine.ownerOf(_mineId) == msg.sender, "Not owner");
        MineInfo memory info = mines[_mineId];
        require(info.wells.length > 0, "Not working");
        require(info.wells[0] == _wellId, "Invalid well id");
        _updatePool();

        IMine.sMine memory m = mine.getTokenTraits(_mineId);
        PoolInfo memory pInfo = poolInfo[m.cid - 1];
        uint256 pending = info.shares.mul(pInfo.accPerShare).div(1e12).sub(info.rewardPaid);
        info.pending = info.pending.add(pending);
        uint256 amount = info.capacity;
        uint256 subShares = info.shares;
        info.capacity = 0;
        info.shares = 0;
        info.power = 0;
        info.rewardPaid = info.shares.mul(pInfo.accPerShare).div(1e12);
        mines[_mineId] = info;
        mines[_mineId].wells.pop();
        pInfo.totalCapacity = pInfo.totalCapacity.sub(amount);
        pInfo.sharesTotal = pInfo.sharesTotal.sub(subShares);
        poolInfo[m.cid - 1] = pInfo;
        well.transferFrom(address(this), _msgSender(), _wellId);
        emit WithdrawWell(msg.sender, _mineId, _wellId);
    }

    function addCapacity(uint32 _mineId, uint256 _capacity) external override {
        require(authControllers[msg.sender] == true, "No auth");
        MineInfo memory info = mines[_mineId];
        if (info.wells.length == 0) {
            return;
        }

        _updatePool();
        IMine.sMine memory m = mine.getTokenTraits(_mineId);
        PoolInfo memory pInfo = poolInfo[m.cid - 1];
        uint256 amount = _capacity;
        uint256 addShares = amount.mul(info.power).div(100);
        uint256 pending = info.shares.mul(pInfo.accPerShare).div(1e12).sub(info.rewardPaid);
        info.pending = info.pending.add(pending);
        info.capacity = info.capacity.add(amount);
        info.shares = info.shares.add(addShares);
        info.rewardPaid = info.shares.mul(pInfo.accPerShare).div(1e12);
        mines[_mineId] = info;
        pInfo.totalCapacity = pInfo.totalCapacity.add(amount);
        pInfo.sharesTotal = pInfo.sharesTotal.add(addShares);
        poolInfo[m.cid - 1] = pInfo;
        emit AddCapacity(_mineId, _capacity);
    }

    function pendingRewards(uint32 _mineId) public view override returns(uint256) {
        if (lastRewardTimestamp == 0) {
            return 0;
        }
        MineInfo memory info = mines[_mineId];
        IMine.sMine memory m = mine.getTokenTraits(_mineId);
        PoolInfo memory pInfo = poolInfo[m.cid - 1];
        uint256 supply = pInfo.sharesTotal;
        uint256 tempAccPerShare = pInfo.accPerShare;
        if (block.timestamp > lastRewardTimestamp && supply != 0) {
            uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256[3] memory eachTypeReward = eachTypeOilReward(multiplier);
            tempAccPerShare = tempAccPerShare.add(eachTypeReward[m.cid - 1].mul(1e12).div(supply));
        }

        uint256 pending = info.pending.add(info.shares.mul(tempAccPerShare).div(1e12).sub(info.rewardPaid));
        return pending;
    }

    function updatePool() external override {
        _updatePool();
    }

    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function isWorkingMine(uint32 _mineId) public view override returns(bool) {
        MineInfo memory info = mines[_mineId];
        if (info.wells.length > 0) {
            return true;
        }
        return false;
    }

    function mineBrief(uint32 _mineId) external view override returns(MineBrief memory) {
        MineInfo memory info = mines[_mineId];
        MineBrief memory brief;
        brief.tokenId = _mineId;
        brief.wells = info.wells;
        brief.power = info.power;
        brief.output = info.capacity;
        IMine.sMine memory m = mine.getTokenTraits(_mineId);
        brief.nftType = m.nftType;
        brief.gen = m.gen;
        brief.capacity = m.capacity;
        brief.cumulativeOutput = m.cumulativeOutput;
        brief.pendingRewards = pendingRewards(_mineId);
        brief.equivalentOutput = treasury.getAmountOut(IOil(oil).pair(), oil, brief.pendingRewards);
        if (brief.equivalentOutput > info.capacity) {
            brief.equivalentOutput = info.capacity;
            brief.pendingRewards = treasury.getAmountOut(IOil(oil).pair(), pairToken, brief.equivalentOutput);
        }
        brief.lastClaimTime = info.lastClaimTime;
        return brief;
    }

    function totalMineInfo() external view override returns(
        uint8   k_,
        bool    addition_,
        uint32  claimCD_,
        uint32  basePct_,
        uint256 oilPerSec_,
        PoolOilInfo[3] memory info_
    ) {
        k_ = K;
        addition_ = addition;
        claimCD_ = claimCD;
        basePct_ = basePct;
        (uint256 totalPerSec_, uint256[3] memory eachTypePerSec) = eachTypeOilPerSec();
        oilPerSec_ = totalPerSec_;
        for (uint8 i = 0; i < 3; ++i) {
            PoolInfo memory pInfo = poolInfo[i];
            info_[i].cid = pInfo.cid;
            info_[i].basePct = pInfo.basePct;
            info_[i].dynamicPct = pInfo.dynamicPct;
            info_[i].oilPerSec = eachTypePerSec[i];
            info_[i].totalCapacity = pInfo.totalCapacity;
        }
    }

    function realOilPerSec() public view returns(uint256) {
        uint32 k = (addition == true) ? 100 + K : 100 - K;
        uint256 perSec = oilPerSec * k / 100;
        return perSec;
    }

    function eachTypeOilPerSec() public view returns(uint256 totalPerSec_, uint256[3] memory eachTypePerSec_) {
        totalPerSec_ = realOilPerSec();
        uint256 basePerSec= totalPerSec_ * basePct / 100;
        uint256 dynamicPerSec = totalPerSec_ - basePerSec;
        uint256 totalBasePct = poolInfo[0].basePct + poolInfo[1].basePct + poolInfo[2].basePct;
        uint256 totalDynamicPct = poolInfo[0].dynamicPct + poolInfo[1].dynamicPct + poolInfo[2].dynamicPct;

        for (uint8 i = 0; i < 3; ++i) {
            if (totalDynamicPct > 0) {
                eachTypePerSec_[i] = basePerSec * poolInfo[i].basePct / totalBasePct + dynamicPerSec * poolInfo[i].dynamicPct / totalDynamicPct;
            } else {
                eachTypePerSec_[i] = totalPerSec_ * poolInfo[i].basePct / totalBasePct;
            }
        }
    }

    function eachTypeOilReward(uint256 _multiplier) public view returns(uint256[3] memory eachTypeReward_) {
        uint256 totalReward = _multiplier.mul(realOilPerSec());
        if (totalRewardAmount + totalReward > MAX_REWARD_AMOUNT) {
            totalReward = MAX_REWARD_AMOUNT - totalRewardAmount;
        }

        uint256 baseReard = totalReward * basePct / 100;
        uint256 dynamicReward = totalReward - baseReard;
        uint256 totalBasePct = poolInfo[0].basePct + poolInfo[1].basePct + poolInfo[2].basePct;
        uint256 totalDynamicPct = poolInfo[0].dynamicPct + poolInfo[1].dynamicPct + poolInfo[2].dynamicPct;

        for (uint8 i = 0; i < 3; ++i) {
            if (totalDynamicPct > 0) {
                eachTypeReward_[i] = baseReard * poolInfo[i].basePct / totalBasePct + dynamicReward * poolInfo[i].dynamicPct / totalDynamicPct;
            } else {
                eachTypeReward_[i] = totalReward * poolInfo[i].basePct / totalBasePct;
            }
        }
    }

    function withdrawBEP20(address _tokenAddress, address _to, uint256 _amount) public onlyOwner {
        uint256 tokenBal = IERC20(_tokenAddress).balanceOf(address(this));
        if (_amount == 0 || _amount >= tokenBal) {
            _amount = tokenBal;
        }
        IERC20(_tokenAddress).transfer(_to, _amount);
    }

    function _updatePool() internal {
        if (startTimestamp == 0) {
            return;
        }

        if (lastRewardTimestamp == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }

        if (block.timestamp - latestHalvingTimestamp >= halvingCycle && oilPerSec > minOilPerSec) {
            uint256 count = (block.timestamp - latestHalvingTimestamp) / halvingCycle;
            latestHalvingTimestamp += count * halvingCycle;
            for (uint256 i = 0; i < count; ++i) {
                oilPerSec = oilPerSec.div(2);
                if (oilPerSec <= minOilPerSec) {
                    oilPerSec = minOilPerSec;
                    break;
                }
            }
        }

        if (totalRewardAmount >= MAX_REWARD_AMOUNT) {
            lastRewardTimestamp = block.timestamp;
            return;
        }

        uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
        uint256[3] memory eachTypeReward = eachTypeOilReward(multiplier);

        for (uint8 i = 0; i < 3; ++i) {
            PoolInfo memory info = poolInfo[i];
            if (info.sharesTotal > 0) {
                poolInfo[i].accPerShare = info.accPerShare.add(eachTypeReward[i].mul(1e12).div(info.sharesTotal));
                totalRewardAmount += eachTypeReward[i];
            }
        }
        lastRewardTimestamp = block.timestamp;
    }
}