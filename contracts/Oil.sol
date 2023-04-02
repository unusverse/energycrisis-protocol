// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IPancakeFactory.sol";
import "./helpers/ERC20.sol";
import "./helpers/Ownable.sol";


contract Oil is ERC20, Ownable {
    uint256 public buyFee;

    uint256 public sellFee;

    IPancakeRouter02 public router;

    address public pair;

    bool private closeFee;

    uint256 private startTime;

    uint256 private constant blackTime = 1;

    address public feeAccount;

    address public pairToken;

    mapping(address => bool) public blackUser;

    mapping(address => bool) public excludedFeeAccount;

    address public initController;
    mapping(address => bool) public mintControllers;
    uint256 public constant MAX_AMOUNT = 21000000000 * 1e18;

    event AddBlackUser(address indexed account, uint256 time);
    event RemoveBlackUser(address indexed account, uint256 time);

    constructor(
        address _router,
        address _pairToken,
        address _feeAccount
    ) ERC20("Oil Token", "OIL") {
        require(_router != address(0));
        require(_pairToken != address(0));
        require(_feeAccount != address(0));

        mintControllers[msg.sender] = true;
        router = IPancakeRouter02(_router);
        pairToken = _pairToken;
        pair = IPancakeFactory(router.factory()).createPair(
            address(this),
            _pairToken
        );
        IERC20(pair).approve(address(router), type(uint256).max);
        IERC20(pairToken).approve(address(router), type(uint256).max);
        sellFee = 0.05e12;
        buyFee = 0.10e12;
        feeAccount = _feeAccount;
    }

    modifier closeFeeTransfer() {
        require(!closeFee, "in closeFee");
        closeFee = true;
        _;
        closeFee = false;
    }

    
    function setSellFee(uint256 _sellFee) external onlyOwner {
        require(_sellFee < 0.5e12, "sellFee must lt 0.5e12");
        sellFee = _sellFee;
    }

    
    function setBuyFee(uint256 _buyFee) external onlyOwner {
        require(_buyFee < 0.5e12, "sellFee must lt 0.5e12");
        buyFee = _buyFee;
    }


    function setExcludedFeeAccount(address _account, bool _exclude) external onlyOwner {
        excludedFeeAccount[_account] = _exclude;
    } 

    function setFeeAccount(address _feeAccount) external onlyOwner {
        require(_feeAccount != address(0), "wrong address");
        feeAccount = _feeAccount;
    }

    function setInitController(address _controller) external onlyOwner {
        require(_controller != address(0), "wrong address");
        initController = _controller;
    }

    function setMintController(address _controller, bool _enable) external onlyOwner {
        mintControllers[_controller] = _enable;
    }

    function mint(address _account, uint256 _amount) external {
        require(mintControllers[msg.sender] == true, "no auth");
        uint256 totalSupply = totalSupply();
        require(totalSupply + _amount <= MAX_AMOUNT, "more than maximum supply");
        _mint(_account, _amount);
    } 

    function initLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        closeFeeTransfer
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(initController == msg.sender, "No auth!");
        require(startTime == 0, "this is over!");

        if (tokenA == address(this)) {
            _mint(address(this), amountADesired);
            _approve(address(this), address(router), amountADesired);
        } else {
            require(tokenA == pairToken, "tokenA must be pairToken");
            require(
                IERC20(tokenA).transferFrom(
                    msg.sender,
                    address(this),
                    amountADesired
                ),
                "A transferFrom error"
            );
            IERC20(tokenA).approve(address(router), amountADesired);
        }

        if (tokenB == address(this)) {
            _mint(address(this), amountBDesired);
            _approve(address(this), address(router), amountBDesired);
        } else {
            require(tokenB == pairToken, "tokenB must be pairToken");
            require(
                IERC20(tokenB).transferFrom(
                    msg.sender,
                    address(this),
                    amountBDesired
                ),
                "B transferFrom error"
            );
            IERC20(tokenB).approve(address(router), amountBDesired);
        }

        (amountA, amountB, liquidity) = router.addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
        if (amountADesired - amountA > 0) {
            IERC20(tokenA).transfer(msg.sender, amountADesired - amountA);
        }
        if (amountBDesired - amountB > 0) {
            IERC20(tokenB).transfer(msg.sender, amountBDesired - amountB);
        }

        if (startTime == 0) {
            startTime = block.timestamp;
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        uint256 feeAmount = 0;
        if (!closeFee && !excludedFeeAccount[from] && !excludedFeeAccount[to]) {
            if (to == pair) {
                feeAmount += (amount * sellFee) / 1e12;
            }
            else if (from == pair) {
                feeAmount += (amount * buyFee) / 1e12;
                _addBlackUser(to);
            } 
            if (feeAmount > 0) {
                super._transfer(from, feeAccount, feeAmount);
            }
        }
        require(!blackUser[from], "error!");
        super._transfer(from, to, amount - feeAmount);
    }

    function addBlackUser(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (!blackUser[accounts[i]]) {
                blackUser[accounts[i]] = true;
                emit AddBlackUser(accounts[i], block.timestamp);
            }
        }
    }
    
    function removeBlackUser(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (blackUser[accounts[i]]) {
                delete blackUser[accounts[i]];
                emit RemoveBlackUser(accounts[i], block.timestamp);
            }
        }
    }

    function _addBlackUser(address account) internal {
        if (startTime > 0 && block.timestamp < (startTime + blackTime)) {
            if (!blackUser[account] && account != pair) {
                blackUser[account] = true;
                emit AddBlackUser(account, block.timestamp);
            }
        }
    }
}