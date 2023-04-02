// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IFriends {
    function isFriend(address _user, address _friend) external view returns(bool);
    function balanceOfFriends(address _user) external view returns(uint256);
    function getFriends(address _user, uint256 _index, uint8 _len) external view returns(
        address[] memory friends, 
        uint8 len
    );
    function clearUp(uint32 _mineId) external; 
}