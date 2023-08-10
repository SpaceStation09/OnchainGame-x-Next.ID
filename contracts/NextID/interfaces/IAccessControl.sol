//SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./IIdentityGraph.sol";

interface IAccessControl {
    function isValid(
        IIdentityGraph profile,
        bytes calldata signature,
        bytes calldata validationData
    ) external view returns (bool);

    function isAuthorizedToUpgrade(IIdentityGraph profile, address caller) external view returns (bool);
}
