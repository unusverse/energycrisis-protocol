// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "./library/Strings.sol";
import "./library/Base64.sol";
import "./interfaces/ITraits.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract TycoonTraits is OwnableUpgradeable, ITraits {
    using Strings for uint256;
    using Base64 for bytes;

    function initialize() external initializer {
        __Ownable_init();
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        string memory imageUrl = getImageUrl(_tokenId);
        string memory externalUrl = getExternalUrl(_tokenId);

        string memory metadata = string(abi.encodePacked(
            '{"name": "Oil Tycoon #',
            _tokenId.toString(),
            '", "description": "Own the limited edition Oil Tycoon NFT and become the ruler of the oil industry in the Metaverse!", ',
            imageUrl,
            ', ',
            externalUrl,
            "}"
        ));

        return string(abi.encodePacked(
            "data:application/json;base64,",
            bytes(metadata).base64()
        ));
    }

    function getImageUrl(uint256 _tokenId) internal pure returns(string memory) {
        string memory ipfsHash = "Qmf5wH5HkRtNW9bx9oCNR1ie7g1LrGdZuPxhRzy5GFcjH6";
        return string(abi.encodePacked('"image": "https://unus.mypinata.cloud/ipfs/',
            ipfsHash,
            '/',
            _tokenId.toString(),
            '.png"'
        ));
    }

    function getExternalUrl(uint256 _tokenId) internal pure returns(string memory) {
        return string(abi.encodePacked('"external_url": "https://energycrisis.xyz/tycoon/',
            _tokenId.toString(),
            '.png"'
        ));
    }
}