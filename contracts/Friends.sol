// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./interfaces/IFriends.sol";
import "./interfaces/IMineEnumerable.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ICapacityPackage.sol";
import "./interfaces/IMinePool.sol";
import "./interfaces/IOil.sol";
import "./interfaces/IWETH.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract Friends is IFriends, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event AddFriend(address indexed sender, address indexed friend);
    event Help(address indexed sender, uint32 helpMineId, uint256 rewardCapacity);

    struct HelpConfig {
        uint8 maxHelperCount;
        uint8 rewardPercent;
        uint32 helpCD;
    }

    struct HelpRecord {
        uint32 mineId;
        uint32 helpTime;
        uint256 rewardCapacity;
        address helper;
    }

    IMineEnumerable public mine;
    IMinePool public minePool;
    ITreasury public treasury;
    ICapacityPackage public capacityPackage;
    address public oil;
    mapping(address => address[]) public friendsList;
    mapping(address => mapping(address => bool)) public friendsIndices;
    mapping(uint32 => uint8) public helpCountOfMine;
    mapping(address => mapping(uint32 => uint32)) public helpInfo;

    uint8 public maxPerAmount;
    HelpConfig public config;

    HelpRecord[] public helpRecords;
    mapping(address => uint256[]) public helpRecordsOfUser;
    mapping(uint32 => uint256[]) public helpRecordsOfMine;
    uint256 public cost;

    function initialize(
        address _mine,
        address _minePool,
        address _treasury,
        address _capacityPackage,
        address _oil
    ) external initializer {
        require(_mine != address(0));
        require(_minePool != address(0));
        require(_treasury != address(0));
        require(_capacityPackage != address(0));
        require(_oil != address(0));
        __Ownable_init();
        __Pausable_init();
        mine = IMineEnumerable(_mine);
        minePool = IMinePool(_minePool);
        treasury = ITreasury(_treasury);
        capacityPackage = ICapacityPackage(_capacityPackage);
        oil = _oil;
        maxPerAmount = 100;
        config.maxHelperCount = 5;
        config.rewardPercent = 3;
        config.helpCD = 1 days;
        if (treasury.isNativeTokenToPay()) {
            cost = 1 ether;
        } else {
            cost = 2 ether;
        }
    }

    function setMaxPerAmount(uint8 _amount) external onlyOwner {
        require(_amount >= 20);
        maxPerAmount = _amount;
    }

    function setCost(uint256 _cost) external onlyOwner {
        cost = _cost;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    receive() external payable {}

     //_payToken: 0 USDT or WETH, 1 Oil
    function addFriend(address _friend, uint8 _payToken) external payable whenNotPaused {
        require(tx.origin == _msgSender(), "Not EOA");
        require(msg.sender != _friend, "Can't add self");
        require(friendsIndices[msg.sender][_friend] == false, "Already friends");

        (address token, uint256 amount) = treasury.getAmount(_payToken, cost);
        if (treasury.isNativeToken(token)) {
            require(amount == msg.value, "amount != msg.value");
            IWETH(token).deposit{value: msg.value}();
            IERC20(token).safeTransfer(address(treasury), amount);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(treasury), amount);
        }

        friendsIndices[msg.sender][_friend] = true;
        friendsList[msg.sender].push(_friend);
        emit AddFriend(msg.sender, _friend);
    }

    function isFriend(address _user, address _friend) public view override returns(bool) {
        return friendsIndices[_user][_friend];
    }

    function balanceOfFriends(address _user) public view override returns(uint256) {
        return friendsList[_user].length;
    }

    function getFriends(address _user, uint256 _index, uint8 _len) public view override returns(
        address[] memory friends, 
        uint8 len
    ) {
        require(_len <= maxPerAmount && _len != 0);
        friends = new address[](_len);
        len = 0;

        uint256 bal = friendsList[_user].length;
        if (bal == 0 || _index >= bal) {
            return (friends, len);
        }

        for (uint8 i = 0; i < _len; ++i) {
            friends[i] = friendsList[_user][_index];
            ++_index;
            ++len;
            if (_index >= bal) {
                return (friends, len);
            }
        }
    }

    function helperRecordsLength() public view returns(uint256) {
        return helpRecords.length;
    }

    function blanceOfRecords(address _user) public view returns(uint256) {
        return helpRecordsOfUser[_user].length;
    }

    function blanceOfRecords(uint32 _mineId) public view returns(uint256) {
        return helpRecordsOfMine[_mineId].length;
    }

    function getRecords(address _user, uint256 _index, uint8 _len) public view returns(
        HelpRecord[] memory records,
        uint8 len
    ) {
        require(_len <= maxPerAmount && _len != 0);
        records = new HelpRecord[](_len);
        len = 0;

        uint256 bal = helpRecordsOfUser[_user].length;
        if (bal == 0 || _index >= bal) {
            return (records, len);
        }

        for (uint8 i = 0; i < _len; ++i) {
            uint256 pos = helpRecordsOfUser[_user][_index];
            records[i] = helpRecords[pos];
            ++_index;
            ++len;
            if (_index >= bal) {
                return (records, len);
            }
        }
    }

    function getRecords(uint32 _mineId, uint256 _index, uint8 _len) public view returns(
        HelpRecord[] memory records,
        uint8 len
    ) {
        require(_len <= maxPerAmount && _len != 0);
        records = new HelpRecord[](_len);
        len = 0;

        uint256 bal = helpRecordsOfMine[_mineId].length;
        if (bal == 0 || _index >= bal) {
            return (records, len);
        }

        for (uint8 i = 0; i < _len; ++i) {
            uint256 pos = helpRecordsOfMine[_mineId][_index];
            records[i] = helpRecords[pos];
            ++_index;
            ++len;
            if (_index >= bal) {
                return (records, len);
            }
        }
    }

    function help(uint32 _helpMineId) external whenNotPaused {
        require(tx.origin == _msgSender(), "Not EOA");
        address friendAddr = mine.ownerOf(_helpMineId);
        require(isFriend(msg.sender, friendAddr), "Non friend");
        require(minePool.isWorkingMine(_helpMineId), "Not working");
        require(helpCountOfMine[_helpMineId] <= config.maxHelperCount, "Reach the max help count");
        uint32 lastHelpTime = helpInfo[msg.sender][_helpMineId];
        require(block.timestamp > lastHelpTime + config.helpCD, "Countdown");

        minePool.updatePool();
        IMinePool.MineBrief memory brief = minePool.mineBrief(_helpMineId);
        uint256 rewardCapacity = 0;
        if (brief.equivalentOutput > 0) {
            rewardCapacity = brief.equivalentOutput * config.rewardPercent / 100;
            IMine.sMine memory m = mine.getTokenTraits(_helpMineId);
            m.capacity = m.capacity.add(rewardCapacity);
            mine.updateTokenTraits(m);
            minePool.addCapacity(_helpMineId, rewardCapacity);
            capacityPackage.addCapacity(msg.sender, rewardCapacity);
        }
        
        helpCountOfMine[_helpMineId] += 1;
        helpInfo[msg.sender][_helpMineId] = uint32(block.timestamp);

        HelpRecord memory record;
        record.mineId = _helpMineId;
        record.helpTime = uint32(block.timestamp);
        record.rewardCapacity = rewardCapacity;
        record.helper = msg.sender;
        helpRecords.push(record);

        uint256 pos = helpRecords.length - 1;
        helpRecordsOfUser[msg.sender].push(pos);
        helpRecordsOfMine[_helpMineId].push(pos);
        emit Help(msg.sender, _helpMineId, rewardCapacity);
    }

    function clearUp(uint32 _mineId) external override {
        require(msg.sender == address(minePool), "No auth");
        helpCountOfMine[_mineId] = 0;
    }
}