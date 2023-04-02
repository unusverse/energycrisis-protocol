// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../library/SafeMath.sol";
import "../helpers/ERC20.sol";
import "../helpers/Ownable.sol";

contract USDT is ERC20, Ownable {

    using SafeMath for uint256;

    constructor() ERC20("USDT Token", "USDT") {
    }

    function mint(address account_, uint256 amount_) external onlyOwner() {
        _mint(account_, amount_);
    }

    function burn(uint256 amount) public virtual {
        _burn(msg.sender, amount);
    }
     
    function burnFrom(address account_, uint256 amount_) public virtual {
        _burnFrom(account_, amount_);
    }

    function _burnFrom(address account_, uint256 amount_) public virtual {
        uint256 decreasedAllowance_ =
            allowance(account_, msg.sender).sub(
                amount_,
                "ERC20: burn amount exceeds allowance"
            );

        _approve(account_, msg.sender, decreasedAllowance_);
        _burn(account_, amount_);
    }

    function blockNumber() public view returns(uint) {
        return block.number;
    }

    function timestamp() public view returns(uint) {
        return block.timestamp;
    }
}