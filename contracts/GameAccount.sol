//SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@account-abstraction/contracts/core/BaseAccount.sol";
import "@account-abstraction/contracts/samples/callback/TokenCallbackHandler.sol";
import "./NextID/lib/Identity.sol";
import "./NextID/interfaces/IIdentityGraph.sol";

/**
 * Game account.
 *  this is sample game account.
 *  has execute, eth handling methods
 *  use Identity Graph for role-based access control
 */
contract GameAccount is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable {
    using ECDSA for bytes32;

    IIdentityGraph public profile;
    address public avatarAddr;
    string public userName;
    IEntryPoint private immutable _entrypoint;

    event GameAccountInitialized(IEntryPoint indexed entryPoint, address indexed profile, string userName);
    event SwitchProfile(IIdentityGraph indexed _oldProfile, IIdentityGraph indexed _newProfile);

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entrypoint;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    constructor(IEntryPoint anEntryPoint) {
        _entrypoint = anEntryPoint;
        _disableInitializers();
    }

    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external {
        require(_isAuthorizedOrEntryPoint(), "GA: Not authorized caller");
        _call(dest, value, func);
    }

    function executeBatch(
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata func
    ) external {
        require(_isAuthorizedOrEntryPoint(), "GA: Not authorized caller");
        require(
            dest.length == func.length && (value.length == 0 || value.length == func.length),
            "wrong array lengths"
        );
        if (value.length == 0) {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], 0, func[i]);
            }
        } else {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], value[i], func[i]);
            }
        }
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value: msg.value}(address(this));
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
        require(_isAvatar(signature, msgEthHash), "GA: Not Avatar");
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    function setProfile(IIdentityGraph _newProfile, bytes memory signature) external {
        bytes32 msgHash = keccak256(abi.encodePacked(_newProfile));
        bytes32 msgEthHash = msgHash.toEthSignedMessageHash();
        require(_isAvatar(signature, msgEthHash), "GA: Not Avatar");
        emit SwitchProfile(profile, _newProfile);
        profile = _newProfile;
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of GameAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(IIdentityGraph _profile, string memory _userName) public virtual initializer {
        _initialize(_profile, _userName);
    }

    function _initialize(IIdentityGraph _profile, string memory _userName) internal virtual {
        profile = _profile;
        avatarAddr = address(uint160(uint256(keccak256(profile.getAvatar()))));
        userName = _userName;
        emit GameAccountInitialized(entryPoint(), address(_profile), _userName);
    }

    //TBD: require avatar to be msg.sender
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        require(_isAvatar("", ""), "GA: Not Avatar");
    }

    function _isAvatar(bytes memory signature, bytes32 msgEthHash) internal view returns (bool) {
        address caller = signature.length == 0 ? msg.sender : msgEthHash.recover(signature);
        return caller == avatarAddr;
    }

    function _isAuthorizedOrEntryPoint() internal view returns (bool) {
        return msg.sender == address(entryPoint()) || _isAuthorized(msg.sender);
    }

    function _isAuthorized(address sender) internal view returns (bool) {
        if (avatarAddr == sender) return true;
        return profile.isChainIdentityLinked(sender);
    }

    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        override
        returns (uint256 validationData)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address calculatedAddress = hash.recover(userOp.signature);
        bool isValid = _isAuthorized(calculatedAddress);
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
