
// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IWellConfig {
    struct LevelConfig {
        uint32 minSpeedBuf;
        uint32 maxSpeedBuf;
        uint256 cost;
    }
    function price() external view returns(uint256);
    function levelConfig(uint8 _level) external view returns(LevelConfig memory);
}