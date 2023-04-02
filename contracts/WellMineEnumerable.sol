// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./interfaces/IWellEnumerable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract WellEnumerable is OwnableUpgradeable {
    IWellEnumerable public well;
    uint8 public maxPerAmount;

    function initialize(
        address _well
    ) external initializer {
        require(_well != address(0));

        __Ownable_init();

        well = IWellEnumerable(_well);
        maxPerAmount = 100;
    }

    function setMaxPerAmount(uint8 _amount) external onlyOwner {
        require(_amount >= 10 && _amount <= 100);
        maxPerAmount = _amount;
    }

    function balanceOf(address _user) public view returns(uint256) {
        return well.balanceOf(_user);
    }

    function totalSupply() public view returns(uint256) {
        return well.totalSupply();
    }

    function getUserTokenTraits(address _user, uint256 _index, uint8 _len) public view returns(
        IWell.sWell[] memory nfts, 
        uint8 len
    ) {
        require(_len <= maxPerAmount && _len != 0);
        nfts = new IWell.sWell[](_len);
        len = 0;

        uint256 bal = well.balanceOf(_user);
        if (bal == 0 || _index >= bal) {
            return (nfts, len);
        }

        for (uint8 i = 0; i < _len; ++i) {
            uint256 tokenId = well.tokenOfOwnerByIndex(_user, _index);
            nfts[i] = well.getTokenTraits(uint32(tokenId));
            ++_index;
            ++len;
            if (_index >= bal) {
                return (nfts, len);
            }
        }
    }

    function tokenDetails(uint32 _mineId) public view returns(IWell.sWell memory) {
        return well.getTokenTraits(_mineId);
    }
}