// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/ITreasury.sol";
import "./interfaces/ITraits.sol";
import "./interfaces/IWETH.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract Tycoon is OwnableUpgradeable, ERC721EnumerableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Mint(address[] _to);
    event Buy(address indexed sender, uint8 payToken);

    ITraits public traits;
    ITreasury public treasury;

    uint32 public maxG0Amount;
    uint32 public maxSupply;
    uint32 public minted;
    bool public startG1Mint;
    uint256 public price;

    mapping(address => bool) public excludedAccount;

    function initialize(
        address _traits,
        address _treasury
     ) external initializer {
        require(_traits != address(0));
        require(_treasury != address(0));

        __ERC721_init("Oil Tycoon", "Tycoon");
        __ERC721Enumerable_init();
        __Ownable_init();
        __Pausable_init();

        traits = ITraits(_traits);
        treasury = ITreasury(_treasury);
        maxG0Amount = 100;
        maxSupply = 500;
        startG1Mint = false;
    }

    function setMaxG0Amount(uint32 _amount) external onlyOwner {
        maxG0Amount = _amount;
    }

    function setMaxSupply(uint32 _maxSupply) external onlyOwner {
        maxSupply = _maxSupply;
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setStartG1Mint() external onlyOwner {
        require(minted >= maxG0Amount, "G0 mint not finished");
        require(startG1Mint == false, "G1 mint already started");
        startG1Mint = true;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function setExcludedAccount(address _account, bool _exclude) external onlyOwner {
        excludedAccount[_account] = _exclude;
    }

    receive() external payable {}

    function mint(address[] memory _to) external onlyOwner {
        require(_to.length + minted <= maxG0Amount, "more than maxG0Amount");
        for (uint256 i = 0; i < _to.length; ++i) {
            minted++;
            _safeMint(_to[i], minted);
        }
        emit Mint(_to);
    }

    //_payToken: 0 USDT or WETH, 1 Oil
    function buy(uint8 _payToken) external payable whenNotPaused {
        require(tx.origin == _msgSender(), "Not EOA");
        require(startG1Mint == true, "G1 mint not start");
        require(minted < maxSupply, "Reached the max supply");

        (address token, uint256 amount) = treasury.getAmount(_payToken, price);
         if (treasury.isNativeToken(token)) {
            require(amount == msg.value, "amount != msg.value");
            IWETH(token).deposit{value: msg.value}();
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        IERC20(token).safeTransfer(address(treasury), amount);
        treasury.buyBack(_payToken, amount);
        minted++;
        _safeMint(msg.sender, minted);
        emit Buy(msg.sender, _payToken);
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId));
        return traits.tokenURI(_tokenId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override {
        super._beforeTokenTransfer(from, to, tokenId);
        if (excludedAccount[to]) {
            return;
        }
        require(to == address(0) || balanceOf(to) == 0, "An address can only have one nft");
    }
}