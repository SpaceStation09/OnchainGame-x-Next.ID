// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./GameAccount.sol";
import "./NextID/interfaces/IIdentityGraph.sol";

contract AccountFactory {
    GameAccount public immutable accountImp;

    constructor(IEntryPoint _entryPoint) {
        accountImp = new GameAccount(_entryPoint);
    }

    function createAccount(
        IIdentityGraph _profile,
        string memory _userName,
        uint256 _salt
    ) public returns (GameAccount ret) {
        address addr = getAddress(_profile, _userName, _salt);
        uint256 codeSize = addr.code.length;
        if (codeSize > 0) {
            return GameAccount(payable(addr));
        } else {
            ret = GameAccount(
                payable(
                    new ERC1967Proxy{salt: bytes32(_salt)}(
                        address(accountImp),
                        abi.encodeCall(GameAccount.initialize, (_profile, _userName))
                    )
                )
            );
        }
    }

    function getAddress(
        IIdentityGraph _profile,
        string memory _userName,
        uint256 _salt
    ) public view returns (address) {
        return
            Create2.computeAddress(
                bytes32(_salt),
                keccak256(
                    abi.encodePacked(
                        type(ERC1967Proxy).creationCode,
                        abi.encode(address(accountImp), abi.encodeCall(GameAccount.initialize, (_profile, _userName)))
                    )
                )
            );
    }
}
