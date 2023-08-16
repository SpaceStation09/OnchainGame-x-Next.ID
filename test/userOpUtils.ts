import { ecsign, keccak256 as keccak256_buffer, toRpcSig } from "ethereumjs-util";
import { Wallet } from "ethers";
import { arrayify, defaultAbiCoder, keccak256 } from "ethers/lib/utils";
import { UserOperation } from "./utils";

export function packUserOp(op: UserOperation, forSignature = true): string {
  if (forSignature) {
    return defaultAbiCoder.encode(
      ["address", "uint256", "bytes32", "bytes32", "uint256", "uint256", "uint256", "uint256", "uint256", "bytes32"],
      [
        op.sender,
        op.nonce,
        keccak256(op.initCode),
        keccak256(op.callData),
        op.callGasLimit,
        op.verificationGasLimit,
        op.preVerificationGas,
        op.maxFeePerGas,
        op.maxPriorityFeePerGas,
        keccak256(op.paymasterAndData),
      ],
    );
  } else {
    // for the purpose of calculating gas cost encode also signature (and no keccak of bytes)
    return defaultAbiCoder.encode(
      ["address", "uint256", "bytes", "bytes", "uint256", "uint256", "uint256", "uint256", "uint256", "bytes", "bytes"],
      [
        op.sender,
        op.nonce,
        op.initCode,
        op.callData,
        op.callGasLimit,
        op.verificationGasLimit,
        op.preVerificationGas,
        op.maxFeePerGas,
        op.maxPriorityFeePerGas,
        op.paymasterAndData,
        op.signature,
      ],
    );
  }
}

export function getUserOpHash(userOp: UserOperation, entryPoint: string, chainId: number): string {
  const userOpHash = keccak256(packUserOp(userOp, true));
  const enc = defaultAbiCoder.encode(["bytes32", "address", "uint256"], [userOpHash, entryPoint, chainId]);
  return keccak256(enc);
}

export function signUserOp(userOp: UserOperation, signer: Wallet, entryPoint: string, chainId: number): UserOperation {
  const message = getUserOpHash(userOp, entryPoint, chainId);
  const msg1 = Buffer.concat([
    Buffer.from("\x19Ethereum Signed Message:\n32", "ascii"),
    Buffer.from(arrayify(message)),
  ]);

  const sig = ecsign(keccak256_buffer(msg1), Buffer.from(arrayify(signer.privateKey)));
  const signedMsg1 = toRpcSig(sig.v, sig.r, sig.s);
  return {
    ...userOp,
    signature: signedMsg1,
  };
}
