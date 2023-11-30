# Agent Case

We develop a smart contract wallet to help establish an agent-specific authorization mechanism.

## Terminology

- `Agent`

- `Account`: Our smart contract wallet which follows the EIP-4337 standard.

- `Access Control Module`: Module works as a plug-in in our mechanism, we can define: valid `target`, valid `function`. i.e. `Access Control Module` is able to authorize accessability to a specific function in a contract to a keypair of an agent.

## Use Case

- Direct Call: The agent can use its keypair to call `execute()` in `Account` directly to forward the call to the `target` contract.
- UserOp Call: The agent form a `UserOperation` with its keypair and send the `UserOperation` to the mempool (EIP 4337 workflow).

## Gas Report

To test gas, I developed a tic tac toe game as target contract. The recorded gas used amount is listed below:

|               |  EOA   | Account Direct Call | Account UserOp Call |
| ------------- | :----: | :-----------------: | :-----------------: |
| createNewGame | 112932 |       138161        |       195199        |
