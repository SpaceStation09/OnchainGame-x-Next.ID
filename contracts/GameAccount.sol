//SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@account-abstraction/contracts/core/BaseAccount.sol";
import "@account-abstraction/contracts/samples/callback/TokenCallbackHandler.sol";
import "./interfaces/IAccessControl.sol";
import "./NextID/lib/Identity.sol";

/**
 * Game account.
 *  this is sample game account.
 *  has execute, eth handling methods
 *  use Identity Graph for role-based access control
 */
contract GameAccount is BaseAccount, TokenCallbackHandler, UUPSUpgradeable, Initializable {
    using ECDSA for bytes32;

    IIdentityGraph public profile;
    IAccessControl private controlModule;
    string public userName;
    IEntryPoint private immutable _entrypoint;

    event GameAccountInitialized(IEntryPoint indexed entryPoint, address indexed profile, string userName);
    event SwitchProfile(IIdentityGraph indexed _oldProfile, IIdentityGraph indexed _newProfile);
    event SwitchControlModule(IAccessControl indexed _oldModule, IAccessControl indexed _newModule);

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
        _requireAuthorized(signature, msgEthHash, 1);
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    function setProfile(IIdentityGraph _newProfile, bytes memory signature) external {
        bytes32 msgHash = keccak256(abi.encodePacked(_newProfile));
        bytes32 msgEthHash = msgHash.toEthSignedMessageHash();
        _requireAvatar(signature, msgEthHash);
        emit SwitchProfile(profile, _newProfile);
        profile = _newProfile;
    }

    function setControlModule(IAccessControl _controlModule, bytes memory signature) external {
        bytes32 msgHash = keccak256(abi.encodePacked(_controlModule));
        bytes32 msgEthHash = msgHash.toEthSignedMessageHash();
        _requireAvatar(signature, msgEthHash);
        emit SwitchControlModule(controlModule, _controlModule);
        controlModule = _controlModule;
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
        userName = _userName;
        emit GameAccountInitialized(entryPoint(), address(_profile), _userName);
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        _requireAvatar("", "");
    }

    function _requireAvatar(bytes memory signature, bytes32 msgEthHash) internal view {
        address avatarAddr = address(uint160(uint256(keccak256(profile.getAvatar()))));
        if (signature.length == 0) {
            require(msg.sender == avatarAddr, "GA: Only avatar can reset profile");
        } else {
            address calculatedAddress = msgEthHash.recover(signature);
            require(calculatedAddress == avatarAddr, "GA: Set profile signature invalid");
        }
    }

    /**
     * require the request sender is authorized i.e. satisfy control module or in profile
     * @param signature request sender sign with their keypair
     * @param msgEthHash the eth hash of the payload to be signed
     * @param validationData role-based control related info (used in control module):
     *          0 - from _isAuthorizedOrEntryPoint()
     *          1 - from withdrawDepositTo()
     *          2 - from _validateSignature() for erc4337 userop verification usage
     */
    function _requireAuthorized(
        bytes memory signature,
        bytes32 msgEthHash,
        uint256 validationData
    ) internal view {
        if (signature.length == 0) {
            require(_isAuthorized(msg.sender, validationData), "GA: Not authorized");
        } else {
            address calculatedAddress = msgEthHash.recover(signature);
            require(_isAuthorized(calculatedAddress, validationData), "GA: Not authorized");
        }
    }

    function _isAuthorizedOrEntryPoint() internal view returns (bool) {
        return msg.sender == address(entryPoint()) || _isAuthorized(msg.sender, 0);
    }

    function _isAuthorized(address sender, uint256 validationData) internal view returns (bool) {
        if (address(controlModule) == address(0)) {
            Identity memory identity = Identity("Ethereum", Strings.toHexString(sender));
            return profile.isIdentityLinked(identity);
        } else {
            return controlModule.isValid(profile, sender, validationData);
        }
    }

    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        internal
        virtual
        override
        returns (uint256 validationData)
    {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address calculatedAddress = hash.recover(userOp.signature);
        bool isValid = _isAuthorized(calculatedAddress, 2);
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
