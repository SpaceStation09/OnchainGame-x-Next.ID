//SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./interfaces/IAccessControl.sol";
import "./NextID/interfaces/IIdentityGraph.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BlackListAccessControl is IAccessControl, Ownable {
    mapping(address => mapping(uint256 => bool)) public ethAccountBlackList;

    event SetBlackListAccount(address account, uint256 item, bool isBlacklisted);

    function isValid(
        IIdentityGraph profile,
        address caller,
        uint256 validationData
    ) public view returns (bool valid) {
        address avatarAddr = address(uint160(uint256(keccak256(profile.getAvatar()))));
        if (avatarAddr == caller) return true;
        Identity memory identity = Identity("Ethereum", Strings.toHexString(caller));
        if ((!ethAccountBlackList[caller][validationData]) && (profile.isIdentityLinked(identity))) return true;
        return false;
    }

    function setBlackList(
        address account,
        uint256 item,
        bool isBlacklisted
    ) public onlyOwner {
        ethAccountBlackList[account][item] = isBlacklisted;
        emit SetBlackListAccount(account, item, isBlacklisted);
    }
}
