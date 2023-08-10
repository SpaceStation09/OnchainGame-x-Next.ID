//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IdentityGraph.sol";

contract IGFactory {
    event Deployed(address createdContract);

    /**
     * @notice Deploys `initCode` using `salt` for defining the deterministic address.
     * @param initCode Initialization code.
     * @return createdContract Created contract address.
     */
    function deploy(bytes memory initCode) public returns (address payable createdContract) {
        bytes32 dafaultSalt = bytes32(0);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            createdContract := create2(0, add(initCode, 0x20), mload(initCode), dafaultSalt)
        }

        require(createdContract != address(0), "IGFactory: Create2 failed");
        emit Deployed(createdContract);
    }
}
