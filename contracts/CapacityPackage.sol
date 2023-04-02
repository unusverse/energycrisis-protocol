// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract CapacityPackage is OwnableUpgradeable {

    mapping(address => uint256) public userCapacityPacakage;
    mapping(address => bool) public authControllers;

    function initialize() external initializer {
        __Ownable_init();
    }

    function setAuthControllers(address _contracts, bool _enable) external onlyOwner {
        authControllers[_contracts] = _enable;
    }

    function addCapacity(address[] memory _accounts, uint256[] memory _capacity) external {
        require(authControllers[_msgSender()], "no auth");
        require(_accounts.length == _capacity.length, "Invalid params");

        for (uint256 i = 0; i < _accounts.length; ++i) {
            if (_accounts[i] == address(0)) {
                continue;
            }
            userCapacityPacakage[_accounts[i]] += _capacity[i];
        }
    }

    function addCapacity(address _account, uint256 _capacity) external {
        require(authControllers[_msgSender()], "no auth");
        require(_account != address(0), "Invalid address");
        userCapacityPacakage[_account] += _capacity;
    }

    function subCapacity(address _account, uint256 _capacity) external {
        require(authControllers[_msgSender()], "no auth");
        require(userCapacityPacakage[_account] >= _capacity, "Not enough capacity");
        userCapacityPacakage[_account] -= _capacity;
    }
}