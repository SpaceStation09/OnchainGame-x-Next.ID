// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./interfaces/IIdentityGraph.sol";
import "./IdentityGraph.sol";
import "./lib/Identity.sol";

contract QueryIdentityGraph {
    address public igFactory;
    bytes32 public dafaultSalt = bytes32(0);

    constructor(address _igFactory) {
        igFactory = _igFactory;
    }

    function isBind(
        bytes calldata avatar,
        Identity memory identityA,
        Identity memory identityB
    ) external view returns (bool) {
        return
            getIdentityGraph(avatar).isIdentityLinked(identityA) &&
            getIdentityGraph(avatar).isIdentityLinked(identityB);
    }

    function getBindingIdentitiesByPlatform(bytes memory avatar, string[] memory platform)
        external
        view
        returns (Identity[] memory)
    {
        bytes32[] memory identitiesHashList;
        uint256 i;
        uint256 j;
        uint256 count;

        IIdentityGraph ig = getIdentityGraph(avatar);
        uint256 totalLen = ig.getTotalIdentityAmount();
        Identity[] memory returnedIdentitityList = new Identity[](totalLen);
        for (i = 0; i < platform.length; i++) {
            identitiesHashList = ig.getAllNeighborsByPlatform(platform[i]);
            for (j = 0; j < identitiesHashList.length; j++) {
                returnedIdentitityList[count++] = ig.getIdentityByHash(identitiesHashList[j]);
            }
        }

        return returnedIdentitityList;
    }

    function getIdentityGraph(bytes memory avatar) public view returns (IIdentityGraph) {
        bytes memory bytecode = type(IdentityGraph).creationCode;
        bytes memory initCode = abi.encodePacked(bytecode, abi.encode(avatar));
        bytes32 create2hash = keccak256(abi.encodePacked(bytes1(0xff), igFactory, dafaultSalt, keccak256(initCode)));
        // NOTE: cast last 20 bytes of hash to address
        return IIdentityGraph(address(uint160(uint256(create2hash))));
    }
}
