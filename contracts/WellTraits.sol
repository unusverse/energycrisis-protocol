// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./library/Strings.sol";
import "./library/Base64.sol";
import "./interfaces/ITraits.sol";
import "./interfaces/IWell.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract WellTraits is OwnableUpgradeable, ITraits {
    using Strings for uint256;
    using Base64 for bytes;

    IWell public nft;

    function initialize() external initializer {
        __Ownable_init();
    }

    function setNft(address _nft) external onlyOwner {
        require(_nft != address(0));
        nft = IWell(_nft);
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        IWell.sWell memory w = nft.getTokenTraits(_tokenId);
        string memory imageUrl = getImageUrl(w);
        string memory externalUrl = getExternalUrl(w);

        string memory metadata = string(abi.encodePacked(
            '{"name": "EnergyCrisis Well #',
            _tokenId.toString(),
            '", "description": "Set up a Drilling Rig to extract oil from the ground!", ',
            imageUrl,
            ', ',
            externalUrl,
            ', "attributes":',
            compileAttributes(w),
            "}"
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            bytes(metadata).base64()
        ));
    }

    function compileAttributes(IWell.sWell memory _w) internal pure returns (string memory) { 
        string memory traits;
        traits = string(abi.encodePacked(
            attributeForTypeAndValue("Level", uint256(_w.level).toString())
        ));
    
        return string(abi.encodePacked(
            '[',
            traits,
            ']'
        ));
    }

    function attributeForTypeAndValue(string memory _traitType, string memory _value) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"',
            _traitType,
            '","value":"',
            _value,
            '"}'
        ));
    }

    function getImageUrl(IWell.sWell memory _w) internal pure returns(string memory) {
        string memory ipfsHash = "QmSsRtjL61k27r3PFzwads6KmnCcmQPcL249Mrr2uV5ZYJ";
        return string(abi.encodePacked('"image": "https://unus.mypinata.cloud/ipfs/',
            ipfsHash,
            '/well',
            uint256(_w.level).toString(),
            '.png"'
        ));
    }

    function getExternalUrl(IWell.sWell memory _w) internal pure returns(string memory) {
        return string(abi.encodePacked('"external_url": "https://energycrisis.xyz/oil/',
            'well',
            uint256(_w.level).toString(),
            '.png"'
        ));
    }
}