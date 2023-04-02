// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IOil {
    function pair() external view returns(address);
    function initLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external;
    function mint(address _account, uint256 _amount) external;
}