// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./IWell.sol";
import "./IERC721Enumerable.sol";

interface IWellEnumerable is IWell, IERC721Enumerable {}