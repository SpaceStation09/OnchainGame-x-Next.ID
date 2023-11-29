// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./Account.sol";

contract AgentAccountFactory {
    Account public immutable accountImp;

    constructor(IEntryPoint _entryPoint) {
        accountImp = new Account(_entryPoint);
    }

    function createAccount(address _avatarAddr, uint256 _salt) public returns (Account ret) {
        address addr = getAddress(_avatarAddr, _salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return Account(payable(addr));
        } else {
            ret = Account(
                payable(
                    new ERC1967Proxy{salt: bytes32(_salt)}(
                        address(accountImp),
                        abi.encodeCall(Account.initialize, (_avatarAddr))
                    )
                )
            );
        }
    }

    function getAddress(address _avatarAddr, uint256 _salt) public view returns (address) {
        return
            Create2.computeAddress(
                bytes32(_salt),
                keccak256(
                    abi.encodePacked(
                        type(ERC1967Proxy).creationCode,
                        abi.encode(address(accountImp), abi.encodeCall(Account.initialize, (_avatarAddr)))
                    )
                )
            );
    }
}
