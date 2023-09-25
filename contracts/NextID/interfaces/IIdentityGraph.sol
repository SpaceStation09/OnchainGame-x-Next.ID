//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lib/Identity.sol";

interface IIdentityGraph {
    function getAvatar() external view returns (bytes memory);

    function getIdentityAmount(string[] memory platforms) external view returns (uint256);

    function getAllNeighborsByPlatform(string memory platform) external view returns (bytes32[] memory neighbors);

    function getIdentityByHash(bytes32 identityHash) external view returns (Identity memory identity);

    function isIdentityLinked(Identity memory identity) external view returns (bool linked);

    function isChainIdentityLinked(address sessionKey) external view returns (bool linked);
}
