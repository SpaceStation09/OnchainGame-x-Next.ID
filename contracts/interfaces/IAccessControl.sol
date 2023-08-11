//SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../NextID/interfaces/IIdentityGraph.sol";

interface IAccessControl {
    function isValid(
        IIdentityGraph profile,
        address caller,
        uint256 validationData
    ) external view returns (bool);
}
