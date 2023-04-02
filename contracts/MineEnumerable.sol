// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IMineEnumerable.sol";
import "./interfaces/IMinePool.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MineEnumerable is OwnableUpgradeable {
    IMineEnumerable public mine;
    IMinePool public minePool;
    uint8 public maxPerAmount;

    function initialize(
        address _mine,
        address _minePool
    ) external initializer {
        require(_mine != address(0));
        require(_minePool != address(0));

        __Ownable_init();

        mine = IMineEnumerable(_mine);
        minePool = IMinePool(_minePool);
        maxPerAmount = 100;
    }

    function setMine(address _mine) external onlyOwner {
        require(_mine != address(0));
        mine = IMineEnumerable(_mine);
    }

    function setMaxPerAmount(uint8 _amount) external onlyOwner {
        require(_amount >= 10 && _amount <= 100);
        maxPerAmount = _amount;
    }

    function balanceOf(address _user) public view returns(uint256) {
        return mine.balanceOf(_user);
    }

    function totalSupply() public view returns(uint256) {
        return mine.totalSupply();
    }

    function getUserTokenTraits(address _user, uint256 _index, uint8 _len) public view returns(
        IMinePool.MineBrief[] memory nfts, 
        uint8 len
    ) {
        require(_len <= maxPerAmount && _len != 0);
        nfts = new IMinePool.MineBrief[](_len);
        len = 0;

        uint256 bal = mine.balanceOf(_user);
        if (bal == 0 || _index >= bal) {
            return (nfts, len);
        }

        for (uint8 i = 0; i < _len; ++i) {
            uint256 tokenId = mine.tokenOfOwnerByIndex(_user, _index);
            nfts[i] = minePool.mineBrief(uint32(tokenId));
            ++_index;
            ++len;
            if (_index >= bal) {
                return (nfts, len);
            }
        }
    }

    function tokenDetails(uint32 _mineId) public view returns(IMinePool.MineBrief memory) {
        return minePool.mineBrief(_mineId);
    }
}