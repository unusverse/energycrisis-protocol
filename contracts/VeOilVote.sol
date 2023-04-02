// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "./VeOil.sol";
import "./interfaces/IMinePool.sol";

contract VeOilVote is  OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event VoteDynamicPct(address _user, uint256 _voteIndex, uint8 _voteType, uint256 _voteAmount);

    struct UserVoteInfo {
        uint8 voteType;
        uint32 voteTime;
        address user;
        uint256 voteAmount;
    }

    struct VoteDynamicPctInfo {
        uint32 startTime;
        uint32 endTime;
        uint256 totalVoteAmount;
        uint256[] eachTypeVoteAmount;
        uint256[] userVoteIndex;
    }

    VeOil public veOil;
    IMinePool public minePool;
    uint32 public voteDynamicPctDuration;
    uint32 public voteDynamicPctCountdown;
    VoteDynamicPctInfo [] public voteDynamicPctInfo;
    UserVoteInfo [] public userVoteInfo;

    function initialize(
        VeOil _veOil,
        IMinePool _minePool
    ) public initializer {
        __Ownable_init();

        require(address(_veOil) != address(0), "VeOilVote: unexpected zero address for _veOil");
        require(address(_minePool) != address(0), "VeOilVote: unexpected zero address for _minePool");
        veOil = _veOil;
        minePool = _minePool;
        voteDynamicPctDuration = 7 days;
        voteDynamicPctCountdown = 8 hours;
    }

    function setVoteDynamicPctDuration(uint32 _duration) external onlyOwner {
        voteDynamicPctDuration = _duration;
    }

    function setVoteDynamicPctCountdown(uint32 _countdown) external onlyOwner {
        voteDynamicPctCountdown = _countdown;
    }

    function startFirstVoteDynamicPct(uint32 _startTime) external onlyOwner {
        require(voteDynamicPctInfo.length == 0, "voteDynamicPctInfo.length > 0");
        require(_startTime >= block.timestamp, "_startTime < block.timestamp");
        _startVoteDynamicPct(_startTime);
    }

    function executeVoteDynamicPct() external {
        VoteDynamicPctInfo memory info;
        info = voteDynamicPctInfo[voteDynamicPctInfo.length - 1];
        require(block.timestamp >= info.endTime && info.endTime > 0, "Invlid execute time");

        uint256[3] memory dynamicPct;
        for (uint8 i = 0; i < 3; ++i) {
            dynamicPct[i] = info.eachTypeVoteAmount[i];
        }
        minePool.voteDynamicPct(dynamicPct);
        _startVoteDynamicPct(uint32(block.timestamp + voteDynamicPctCountdown));
    }

    function voteDynamicPct(uint8 _voteType, uint256 _voteAmount) external {
        require(_voteType >= 1 && _voteType <= 3, "Invalid vote type"); 
        require(_voteAmount >= 1, "vote amount must be more than 1");
        uint256 realVoteAmount = _voteAmount.mul(1e18);
        uint256 userVeOilBalance = veOil.balanceOf(_msgSender());
        require(userVeOilBalance >= realVoteAmount, "Not enough veOil amount");
        veOil.burnFrom(_msgSender(), realVoteAmount);
        uint256 voteIndex = voteDynamicPctInfo.length - 1;
        VoteDynamicPctInfo memory info = voteDynamicPctInfo[voteIndex];
        require(block.timestamp >= info.startTime && block.timestamp < info.endTime, "Invalid vote time");
        info.eachTypeVoteAmount[_voteType - 1] += _voteAmount;
        info.totalVoteAmount += _voteAmount;
        voteDynamicPctInfo[voteIndex] = info;

        UserVoteInfo memory userVote;
        userVote.voteType = _voteType;
        userVote.voteTime = uint32(block.timestamp);
        userVote.user = _msgSender();
        userVote.voteAmount = _voteAmount;
        userVoteInfo.push(userVote);
        voteDynamicPctInfo[voteIndex].userVoteIndex.push(userVoteInfo.length - 1);
        emit VoteDynamicPct(_msgSender(), voteIndex, _voteType, _voteAmount);
    }

    function voteDynamicPctInfoLength() public view returns(uint256) {
        return voteDynamicPctInfo.length;
    }

    struct VoteDynamicPctDetails {
        uint32 startTime;
        uint32 endTime;
        uint256 voteCount;
        uint256 totalVoteAmount;
        uint256[3] eachTypeVoteAmount;
    }

    function currentVoteDaymicPctDetails() public view returns(VoteDynamicPctDetails memory) {
        VoteDynamicPctDetails memory detail;
        if (voteDynamicPctInfo.length > 0) {
            VoteDynamicPctInfo memory info = voteDynamicPctInfo[voteDynamicPctInfo.length - 1];
            detail.startTime = info.startTime;
            detail.endTime = info.endTime;
            detail.voteCount = info.userVoteIndex.length;
            detail.totalVoteAmount = info.totalVoteAmount;
            detail.eachTypeVoteAmount[0] = info.eachTypeVoteAmount[0];
            detail.eachTypeVoteAmount[1] = info.eachTypeVoteAmount[1];
            detail.eachTypeVoteAmount[2] = info.eachTypeVoteAmount[2];
        }
        return detail;
    }

    function getVoteDynamicPctDetails(uint256 _index, uint8 _len) public view returns(VoteDynamicPctDetails[] memory details, uint8 len) {
        require(_len <= 100 && _len != 0);
        details = new VoteDynamicPctDetails[](_len);
        len = 0;

        uint256 bal = voteDynamicPctInfoLength();
        if (bal == 0 || _index >= bal) {
            return (details, len);
        }

        for (uint8 i = 0; i < _len; ++i) {
            VoteDynamicPctInfo memory info = voteDynamicPctInfo[_index];
            details[i].startTime = info.startTime;
            details[i].endTime = info.endTime;
            details[i].voteCount = info.userVoteIndex.length;
            details[i].totalVoteAmount = info.totalVoteAmount;
            details[i].eachTypeVoteAmount[0] = info.eachTypeVoteAmount[0];
            details[i].eachTypeVoteAmount[1] = info.eachTypeVoteAmount[1];
            details[i].eachTypeVoteAmount[2] = info.eachTypeVoteAmount[2];
            ++_index;
            ++len;
            if (_index >= bal) {
                return (details, len);
            }
        }
    }

    function getVoteDynamicPctUserInfo(uint256 _voteIndex, uint256 _userVoteIndex, uint8 _len) public view returns(UserVoteInfo[] memory voteInfo, uint8 len) {
        require(_len <= 100 && _len != 0);
        voteInfo = new UserVoteInfo[](_len);
        len = 0;

        VoteDynamicPctInfo memory info = voteDynamicPctInfo[_voteIndex];
        uint256 bal = info.userVoteIndex.length;
        if (bal == 0 || _userVoteIndex >= bal) {
            return (voteInfo, len);
        }

        for (uint8 i = 0; i < _len; ++i) {
            uint256 pos = info.userVoteIndex[_userVoteIndex];
            voteInfo[i] = userVoteInfo[pos];
            ++_userVoteIndex;
            ++len;
            if (_userVoteIndex >= bal) {
                return (voteInfo, len);
            }
        }
    }

    function _startVoteDynamicPct(uint32 _startTime) private {
        VoteDynamicPctInfo memory info;
        info.startTime = _startTime;
        info.endTime = _startTime + voteDynamicPctDuration;
        voteDynamicPctInfo.push(info);
        uint256 pos = voteDynamicPctInfo.length - 1;
        voteDynamicPctInfo[pos].eachTypeVoteAmount.push(0);
        voteDynamicPctInfo[pos].eachTypeVoteAmount.push(0);
        voteDynamicPctInfo[pos].eachTypeVoteAmount.push(0);
    }
}