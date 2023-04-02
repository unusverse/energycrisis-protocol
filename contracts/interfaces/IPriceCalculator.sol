// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

interface IPriceCalculator {
    function priceOfWETH() external view returns(uint256);
    function priceOfToken(address token) external view returns(uint256);
}