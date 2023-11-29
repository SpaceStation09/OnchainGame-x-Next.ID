//SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@account-abstraction/contracts/core/BaseAccount.sol";
import "@account-abstraction/contracts/samples/callback/TokenCallbackHandler.sol";
import "../interfaces/IAccessControl.sol";
import "hardhat/console.sol";

/**
 * Account designed for Agent Authorization scenario
 *  this is a sample smart contract wallet
 *  has execute, eth handling methods
 *  use Access Control Module to control the privileges of Agents
 */

contract Account is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable {
    using ECDSA for bytes32;

    address public avatarAddr;

    IEntryPoint private immutable _entryPoint;
    IAccessControl public _accessControl;

    event GameAccountInitialized(IEntryPoint indexed entryPoint, address avatarAddr);
    event SwitchAccessControlModule(IAccessControl indexed oldModule, IAccessControl indexed newModule);

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    constructor(IEntryPoint anEntryPoint) {
        _entryPoint = anEntryPoint;
        _disableInitializers();
    }

    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external {
        require(_isAuthorizedOrEntryPoint(func), "Account: Not authorized call");
        _call(dest, value, func);
    }

    function setAccessControl(IAccessControl _newAccessControl, bytes memory signature) external {
        bytes32 msgHash = keccak256(abi.encodePacked(_newAccessControl));
        bytes32 msgEthHash = msgHash.toEthSignedMessageHash();
        require(_isAvatar(signature, msgEthHash), "Account: Not Avatar");
        emit SwitchAccessControlModule(_accessControl, _newAccessControl);
        _accessControl = _newAccessControl;
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     * @param signature keyPari sign on withdrawAddress
     */
    function withdrawDepositTo(
        address payable withdrawAddress,
        uint256 amount,
        bytes memory signature
    ) public {
        bytes32 msgHash = keccak256(abi.encodePacked(withdrawAddress));
        bytes32 msgEthHash = msgHash.toEthSignedMessageHash();
        require(_isAvatar(signature, msgEthHash), "Account: Not Avatar");
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of GameAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(address _avatarAddr) public virtual initializer {
        _initialize(_avatarAddr);
    }

    function _initialize(address _avatarAddr) internal virtual {
        avatarAddr = _avatarAddr;
        emit GameAccountInitialized(entryPoint(), avatarAddr);
    }

    //TBD: require avatar to be msg.sender
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        require(_isAvatar("", ""), "GA: Not Avatar");
    }

    function _isAuthorizedOrEntryPoint(bytes memory func) internal view returns (bool) {
        return msg.sender == address(entryPoint()) || _isAuthorized(msg.sender, func);
    }

    function _isAvatar(bytes memory signature, bytes32 msgEthHash) internal view returns (bool) {
        address caller = signature.length == 0 ? msg.sender : msgEthHash.recover(signature);
        return caller == avatarAddr;
    }

    function _isAuthorized(address sender, bytes memory func) internal view returns (bool) {
        if (avatarAddr == sender) return true;
        return _accessControl.isValid(sender, func);
    }

    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        override
        returns (uint256 validationData)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address calculatedAddress = hash.recover(userOp.signature);
        bool isValid = _isAuthorized(calculatedAddress, userOp.callData);
        if (!isValid) return SIG_VALIDATION_FAILED;
        return 0;
    }

    function _call(
        address target,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
