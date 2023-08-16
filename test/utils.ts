import { BigNumberish, Contract, Wallet } from "ethers";
import { BytesLike, SigningKey, hexDataSlice, parseUnits } from "ethers/lib/utils";
import { ethers, network } from "hardhat";
import { EntryPoint } from "../types";
import { ZERO_ADDRESS } from "./constants";

export async function takeSnapshot() {
  return network.provider.send("evm_snapshot", []);
}

export async function revertToSnapShot(id: string) {
  await network.provider.send("evm_revert", [id]);
}

export interface IdentityStruct {
  platform: string;
  identityValue: string;
}

export enum Action {
  create,
  delete,
}

export const createAvatarKeyPair = (): SigningKey => {
  const sk = new ethers.utils.SigningKey(Wallet.createRandom().privateKey);
  return sk;
};

export const calculateMsgHash = (identity: IdentityStruct, action: Action): BytesLike => {
  return ethers.utils.solidityPack(["string", "string", "uint8"], [identity.platform, identity.identityValue, action]);
};

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
