//SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../NextID/interfaces/IIdentityGraph.sol";

interface IAccessControl {
    function isValid(address sender, bytes memory _calldata) external view returns (bool);
}
