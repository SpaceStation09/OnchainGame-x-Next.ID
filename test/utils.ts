import { Wallet } from "ethers";
import { BytesLike, SigningKey } from "ethers/lib/utils";
import { ethers, network } from "hardhat";

export async function takeSnapshot() {
  return network.provider.send("evm_snapshot", []);
}

export async function revertToSnapShot(id: string) {
  await network.provider.send("evm_revert", [id]);
}

export interface IdentityStruct {
  platform: string;
  identityValue: string;
  chainIdentity: string;
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
  return ethers.utils.solidityPack(
    ["string", "string", "address", "uint8"],
    [identity.platform, identity.identityValue, identity.chainIdentity, action],
  );
};

// state: 1 for player1 win; 2 for player 2 win; 0 for ongoing game; 3 for draw
export const checkBoard = (gameBoard: number): { player1Turn: boolean; state: number } => {
  let player1Turn = true;
  let state = 0;
  if (((gameBoard >> 18) & 1) == 1) player1Turn = false;
  if (((gameBoard >> 19) & 1) == 0) {
    if (((gameBoard >> 20) & 1) == 0) {
      // 00 = player 1 win
      state = 1;
    } else {
      // 10 = ongoing game
      state = 0;
    }
  } else {
    if (((gameBoard >> 20) & 1) == 0) {
      // 01 = player 2 win
      state = 1;
    } else {
      // 11 = draw
      state = 3;
    }
  }
  return {
    player1Turn,
    state,
  };
};
