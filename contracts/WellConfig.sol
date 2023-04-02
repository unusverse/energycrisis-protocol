// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IWellConfig.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract WellConfig is IWellConfig, OwnableUpgradeable {

    mapping(uint8 => LevelConfig) public configs;

    function initialize(
    ) external initializer {
        __Ownable_init();
    }

    function setConfigs(LevelConfig[] memory _configs) external onlyOwner {
        for (uint8 i = 0; i < _configs.length; ++i) {
            configs[i] = _configs[i];
        }
    }

    function price() external override view returns(uint256) {
        return configs[0].cost;
    }

    function levelConfig(uint8 _level) external override view returns(LevelConfig memory) {
        require(_level > 0, "Invalid level");
        return configs[_level - 1];
    }
}