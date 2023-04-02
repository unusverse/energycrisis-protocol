// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IWell.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ITraits.sol";
import "./interfaces/IWellConfig.sol";
import "./interfaces/IRandom.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "./interfaces/IWETH.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

contract Well is IWell, OwnableUpgradeable, ERC721EnumerableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event UpdateTraits(sWell w);
    event Mint(address indexed account, sWell w);
    event Buy(address indexed account, uint8 payToken, sWell w);

    ITraits public traits;
    IWellConfig public config;
    ITreasury public treasury;
    IRandom public random;
    mapping(uint32 => sWell) public tokenTraits;
    mapping(address => bool) public authControllers;
    uint32 public minted;

    function initialize(
        address _traits,
        address _config,
        address _treasury,
        address _random
    ) external initializer {
        require(_traits != address(0));
        require(_config != address(0));
        require(_treasury != address(0));
        require(_random != address(0));

        __ERC721_init("EnergyCrisis Well", "ECW");
        __ERC721Enumerable_init();
        __Ownable_init();

        traits = ITraits(_traits);
        config = IWellConfig(_config);
        treasury = ITreasury(_treasury);
        random = IRandom(_random);
    }

    function setAuthControllers(address _contracts, bool _enable) external onlyOwner {
        authControllers[_contracts] = _enable;
    }

    function setRandom(address _random) external onlyOwner {
        require(_random != address(0));
        random = IRandom(_random);
    }

    receive() external payable {}

    function buy(uint8 _payToken) payable external {
        require(tx.origin == _msgSender(), "Not EOA");
        uint256 price = config.price();
        (address token, uint256 amount) = treasury.getAmount(_payToken, price);
        if (treasury.isNativeToken(token)) {
            require(amount == msg.value, "amount != msg.value");
            IWETH(token).deposit{value: msg.value}();
            IERC20(token).safeTransfer(address(treasury), amount);
        }  else {
            IERC20(token).safeTransferFrom(msg.sender, address(treasury), amount);
        }
        sWell memory w = _mint(msg.sender);
        emit Buy(msg.sender, _payToken, w);
    }

    function mint(address _to) external override {
        require(authControllers[_msgSender()], "no auth");
        sWell memory w = _mint(_to);
        emit Mint(_to, w);
    }

    function updateTokenTraits(sWell memory _w) external override {
        require(authControllers[_msgSender()], "no auth");
        tokenTraits[_w.tokenId] = _w;
        emit UpdateTraits(_w);
    }

    function getTokenTraits(uint256 _tokenId) external view override returns (sWell memory) {
        return tokenTraits[uint32(_tokenId)];
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        require(_exists(_tokenId));
        return traits.tokenURI(_tokenId);
    }

    function _mint(address _to) internal returns(sWell memory) {
        sWell memory w;
        w.level = 1;
        w.tokenId = minted + 1;
        IWellConfig.LevelConfig memory c = config.levelConfig(1);
        if (c.maxSpeedBuf == c.minSpeedBuf) {
            w.speedBuf = c.maxSpeedBuf;
        } else {
            uint256 r = random.randomseed(minted);
            w.speedBuf = c.maxSpeedBuf + uint32(r % (c.maxSpeedBuf - c.minSpeedBuf));
        }
        tokenTraits[w.tokenId] = w;
        minted++;
        _safeMint(_to, w.tokenId);
        return w;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        // Hardcode the Auth controllers's approval so that users don't have to waste gas approving
        if (authControllers[_msgSender()] == false)
            require(_isApprovedOrOwner(_msgSender(), tokenId));
        _transfer(from, to, tokenId);
    }
}