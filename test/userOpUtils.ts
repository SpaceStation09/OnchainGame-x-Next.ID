import { ecsign, keccak256 as keccak256_buffer, toRpcSig } from "ethereumjs-util";
import { BigNumber, BigNumberish, Contract, Wallet } from "ethers";
import { arrayify, defaultAbiCoder, hexDataSlice, keccak256, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { EntryPoint } from "../types";
import { ZERO_ADDRESS } from "./constants";

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

export const DEFAULT_USER_OPERATION: UserOperation = {
  sender: ZERO_ADDRESS,
  nonce: 0,
  initCode: "0x",
  callData: "0x",
  callGasLimit: 0,
  verificationGasLimit: 200000,
  preVerificationGas: 21000,
  maxFeePerGas: 0,
  maxPriorityFeePerGas: parseUnits("1", "gwei"),
  paymasterAndData: "0x",
  signature: "0x",
};

export interface UserOperation {
  sender: string;
  nonce: number;
  initCode: string;
  callData: string;
  callGasLimit: BigNumberish;
  verificationGasLimit: BigNumberish;
  preVerificationGas: BigNumberish;
  maxFeePerGas: BigNumberish;
  maxPriorityFeePerGas: BigNumberish;
  paymasterAndData: string;
  signature: string;
}

export const fillUserOp = async (userOp: Partial<UserOperation>, entryPoint?: EntryPoint): Promise<UserOperation> => {
  const userOp1 = { ...userOp };
  const provider = entryPoint?.provider;
  if (!provider) throw new Error("no entry point / provider");
  if (userOp.initCode) {
    const initAddr = hexDataSlice(userOp1.initCode!, 0, 20);
    const initCallData = hexDataSlice(userOp1.initCode!, 20);
    userOp1.nonce = userOp1.nonce == null ? 0 : userOp1.nonce;
    if (userOp1.sender == null) {
      userOp1.sender = await entryPoint!.callStatic
        .getSenderAddress(userOp1.initCode!)
        .catch((e) => e.errorArgs.sender);
    }
    if (userOp1.verificationGasLimit == null) {
      const initEstimate = await provider.estimateGas({
        from: entryPoint.address,
        to: initAddr,
        data: initCallData,
        gasLimit: 1e7,
      });
      userOp1.verificationGasLimit = initEstimate.add(DEFAULT_USER_OPERATION.verificationGasLimit);
    }
  }
  if (userOp1.nonce == null) {
    const senderAccount = new Contract(userOp.sender!, ["function getNonce() view returns(uint256)"], provider);
    userOp1.nonce = await senderAccount["getNonce"]();
  }
  if (userOp.callGasLimit == null && userOp.callData != null) {
    const gasEstimated = await provider.estimateGas({
      from: entryPoint.address,
      to: userOp1.sender,
      data: userOp1.callData,
    });

    userOp1.callGasLimit = gasEstimated;
  }

  userOp1.maxPriorityFeePerGas = userOp1.maxPriorityFeePerGas ?? DEFAULT_USER_OPERATION.maxPriorityFeePerGas;
  if (userOp1.maxFeePerGas == null) {
    const block = await provider.getBlock("latest");
    userOp1.maxFeePerGas = block.baseFeePerGas!.add(userOp1.maxPriorityFeePerGas);
  }

  const userOp2 = fillUserOPDefaults(userOp1);
  return userOp2;
};

export const fillUserOPDefaults = (op: Partial<UserOperation>): UserOperation => {
  const partialUserOp = { ...op };
  for (const key in partialUserOp) {
    if (partialUserOp[key] == null) delete partialUserOp[key];
  }
  const filledUserOp = { ...DEFAULT_USER_OPERATION, ...partialUserOp };
  return filledUserOp;
};

export async function estimateGas(userOp: UserOperation, entryPointAddr: string): Promise<UserOperation> {
  let verificationGas = 100000;
  if (userOp.initCode.length > 0) {
    verificationGas += 3200 + 200 * userOp.initCode.length;
  }
  userOp.verificationGasLimit = verificationGas;
  const estimatedGas =
    (
      await ethers.provider.estimateGas({
        from: entryPointAddr,
        to: userOp.sender,
        data: userOp.callData,
      })
    ).toNumber() * 1.5;
  userOp.callGasLimit = BigNumber.from(Math.floor(estimatedGas));
  return userOp;
}
