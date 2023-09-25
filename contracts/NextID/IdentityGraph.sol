/**
 * @author SpaceStation09
 * @email space_staion09@protonmail.com
 * @create date 2023-05-05
 * @modify date 2023-05-12
 */

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IIdentityGraph.sol";
import "./lib/Identity.sol";

contract IdentityGraph is IIdentityGraph {
    enum Action {
        Create,
        Delete
    }
    // identity graph merkle tree root
    // bytes32 public merkleTreeRoot;
    bytes public avatar;
    mapping(string => bytes32[]) public neighborsByPlatform;
    mapping(bytes32 => Identity) public identityDetail;

    constructor(bytes memory _avatar) {
        avatar = _avatar;
    }

    // FIXME: This is only for demo usage !!! DO NOT use it in production!!!!
    function setIdentityForDemo(Identity memory identity, bytes memory signature) external {
        require(_verifySignature(identity, Action.Create, signature), "Identity Graph: Wrong avatar");
        bytes32 identityHash = _hashIdentity(identity);
        require(bytes(identityDetail[identityHash].platform).length == 0, "Duplicate Identity");

        bytes32[] storage hashArray = neighborsByPlatform[identity.platform];
        hashArray.push(identityHash);
        identityDetail[identityHash] = identity;
    }

    // FIXME: This is only for demo usage !!! DO NOT use it in production!!!!
    function deleteIdentityForDemo(Identity memory identity, bytes memory signature) external {
        require(_verifySignature(identity, Action.Delete, signature), "Identity Graph: Wrong avatar");
        require(this.isIdentityLinked(identity), "Identity Graph: Not linked identity");

        bytes32[] storage hashArray = neighborsByPlatform[identity.platform];
        bytes32 identityHash = _hashIdentity(identity);
        for (uint256 i = 0; i < hashArray.length; i++) {
            if (hashArray[i] == identityHash) hashArray[i] = hashArray[hashArray.length - 1];
        }
        hashArray.pop();
        delete identityDetail[identityHash];
    }

    function getAvatar() external view returns (bytes memory) {
        return avatar;
    }

    function getIdentityAmount(string[] memory platforms) external view returns (uint256 amount) {
        for (uint256 i = 0; i < platforms.length; i++) {
            amount += neighborsByPlatform[platforms[i]].length;
        }
        return amount;
    }

    function getAllNeighborsByPlatform(string memory platform) external view returns (bytes32[] memory neighbors) {
        return neighborsByPlatform[platform];
    }

    function getIdentityByHash(bytes32 identityHash) external view returns (Identity memory identity) {
        return identityDetail[identityHash];
    }

    function isIdentityLinked(Identity memory identity) external view returns (bool linked) {
        bytes32 identityHash = _hashIdentity(identity);
        Identity memory recordedIdentity = identityDetail[identityHash];
        if (_equals(recordedIdentity.platform, "")) return false;
        return true;
    }

    function isChainIdentityLinked(address sessionKey) external view returns (bool linked) {
        bytes32 identityHash = keccak256(abi.encodePacked("Ethereum", sessionKey));
        if (identityDetail[identityHash].chainIdentity == address(0)) return false;
        return true;
    }

    function _hashIdentity(Identity memory identity) internal pure returns (bytes32) {
        if (identity.chainIdentity == address(0))
            return keccak256(abi.encodePacked(identity.platform, identity.identityValue));
        return keccak256(abi.encodePacked(identity.platform, identity.chainIdentity));
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encode(a)) == keccak256(abi.encode(b)));
    }

    function _calculateAddress(bytes memory _avatar) internal pure returns (address) {
        return address(uint160(uint256(keccak256(_avatar))));
    }

    function _verifySignature(
        Identity memory identity,
        Action action,
        bytes memory signature
    ) internal view returns (bool) {
        address avatarAddr = _calculateAddress(avatar);
        bytes32 msgHash = keccak256(
            abi.encodePacked(identity.platform, identity.identityValue, identity.chainIdentity, action)
        );
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHash = keccak256(abi.encodePacked(prefix, msgHash));
        address calculatedVerifier = ECDSA.recover(prefixedHash, signature);
        return (calculatedVerifier == avatarAddr);
    }
}
