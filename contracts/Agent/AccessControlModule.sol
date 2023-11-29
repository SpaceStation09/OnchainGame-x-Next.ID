//SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../interfaces/IAccessControl.sol";

contract AgentAccessControl is IAccessControl {
    address public agent;
    address public wallet;
    bytes4 public executeSelector = bytes4(keccak256(bytes("execute(address,uint256,bytes)")));
    mapping(bytes4 => bool) public approvedSelector;

    constructor(address _agent, address _wallet) {
        agent = _agent;
        wallet = _wallet;
    }

    modifier onlyAuthorized() {
        require(msg.sender == agent || msg.sender == wallet, "Access Control: Not Authorized");
        _;
    }

    function isValid(address sender, bytes calldata _calldata) external view returns (bool) {
        if (sender != agent) return false;
        bytes4 functionSelector = bytes4(_calldata[0:4]);
        if (functionSelector == executeSelector) {
            // see offset description at https://github.com/SpaceStation09/OnchainGame-x-Next.ID/blob/agent/docs/CallData.md
            bytes memory func = _calldata[132:];
            functionSelector = bytes4(func);
        }
        return approvedSelector[functionSelector];
    }

    function setValidFunction(string calldata _func, bool _isValid) external onlyAuthorized {
        bytes4 functionSelector = bytes4(keccak256(bytes(_func)));
        approvedSelector[functionSelector] = _isValid;
    }
}
