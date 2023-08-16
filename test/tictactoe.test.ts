import { EntryPoint, EntryPoint__factory } from "@account-abstraction/contracts";
import { expect } from "chai";
import { BigNumber, Signer, Wallet, utils } from "ethers";
import { SigningKey } from "ethers/lib/utils";
import { ethers, network } from "hardhat";
import { take } from "lodash";
import {
  AccountFactory,
  AccountFactory__factory,
  GameAccount,
  GameAccount__factory,
  IdentityGraph,
  IdentityGraph__factory,
  TicTacToe,
  TicTacToe__factory,
} from "../types";
import { ONE_ETH } from "./constants";
import { signUserOp } from "./userOpUtils";
import {
  Action,
  IdentityStruct,
  UserOperation,
  calculateMsgHash,
  createAvatarKeyPair,
  fillUserOPDefaults,
  revertToSnapShot,
  takeSnapshot,
} from "./utils";

describe("TicTacToe Test", () => {
  let signers: Signer[];
  let deployer: Signer;
  let ticTacToe: TicTacToe;
  let player1: Signer;
  let player1Address: string;
  let player2: Signer;
  let player2Address: string;
  let snapshotId: string;

  let scPlayer: GameAccount;
  let accountFactory: AccountFactory;
  let entryPoint: EntryPoint;
  let profile: IdentityGraph;
  let sessionKey: Wallet;
  let avatar: string;
  let avatarKeyPair: SigningKey;

  before(async () => {
    signers = await ethers.getSigners();
    [deployer, player1, player2] = take(signers, 3);
    player1Address = await player1.getAddress();
    player2Address = await player2.getAddress();
    ticTacToe = await new TicTacToe__factory(deployer).deploy();

    avatarKeyPair = createAvatarKeyPair();
    avatar = `0x${avatarKeyPair.publicKey.substring(4)}`;
    profile = await new IdentityGraph__factory(deployer).deploy(avatar);

    entryPoint = await new EntryPoint__factory(deployer).deploy();
    accountFactory = await new AccountFactory__factory(deployer).deploy(entryPoint.address);
    scPlayer = (await createGameAccount(deployer, profile.address, "SpaceStation09", accountFactory)).proxy;
    scPlayer.addDeposit({ value: ONE_ETH });
  });

  beforeEach(async () => {
    snapshotId = await takeSnapshot();
  });

  afterEach(async () => {
    await revertToSnapShot(snapshotId);
  });

  it("normal workflow with EOA", async () => {
    await ticTacToe.createNewGame(player1Address, player2Address);

    // o x o
    // o x _
    // _ x _
    await ticTacToe.connect(player1).makeMove(0, 0);
    await expect(ticTacToe.connect(player1).makeMove(1, 0)).to.be.revertedWith("Not your turn");

    await ticTacToe.connect(player2).makeMove(1, 0);
    await ticTacToe.connect(player1).makeMove(3, 0);
    await ticTacToe.connect(player2).makeMove(4, 0);
    await ticTacToe.connect(player1).makeMove(2, 0);
    await ticTacToe.connect(player2).makeMove(7, 0);

    const result = (await ticTacToe.queryFilter(ticTacToe.filters.PlayerWin()))[0];
    const winner = result.args.player;
    expect(winner).to.be.eq(player2Address);

    await expect(ticTacToe.connect(player1).makeMove(6, 0)).to.be.revertedWith("Game has ended");
  });

  it("normal workflow with GameAccount", async () => {
    // GameID: 0; Player1: scPlayer; Player2: player2
    await ticTacToe.createNewGame(scPlayer.address, player2Address);

    //#region bind sessionKey
    sessionKey = Wallet.createRandom();
    const signingWallet = new Wallet(avatarKeyPair.privateKey);
    const sessionKeyIdentity: IdentityStruct = {
      platform: "Ethereum",
      identityValue: sessionKey.address.toLowerCase(),
    };
    const msgHashSessionKey = utils.keccak256(calculateMsgHash(sessionKeyIdentity, Action.create));
    const signature = await signingWallet.signMessage(utils.arrayify(msgHashSessionKey));
    await profile.setIdentityForDemo(sessionKeyIdentity, signature);
    //#endregion

    let userOp = fillUserOPDefaults({ sender: scPlayer.address });
    userOp.nonce = (await scPlayer.getNonce()).toNumber();
    const execMove = ticTacToe.interface.encodeFunctionData("makeMove", [0, 0]);
    userOp.callData = scPlayer.interface.encodeFunctionData("execute", [ticTacToe.address, 0, execMove]);
    userOp = await estimateGas(userOp, entryPoint.address);
    const chainId = network.config.chainId ?? 0;
    userOp = signUserOp(userOp, sessionKey, entryPoint.address, chainId);

    const moveTx = await entryPoint.connect(deployer).handleOps([userOp], await deployer.getAddress());
    const moveReceipt = await ethers.provider.getTransactionReceipt(moveTx.hash);
    console.log("GameAccount gasUsed to make a move: ", moveReceipt.gasUsed.toString());
  });

  async function createGameAccount(
    deployer: Signer,
    profile: string,
    userName: string,
    factory: AccountFactory,
  ): Promise<{ proxy: GameAccount; accountImp: string }> {
    const accountImp = await factory.accountImp();
    await factory.createAccount(profile, userName, 0);
    const accountAddr = await factory.getAddress(profile, userName, 0);
    const proxy = GameAccount__factory.connect(accountAddr, deployer);
    return {
      proxy,
      accountImp,
    };
  }

  async function estimateGas(userOp: UserOperation, entryPointAddr: string): Promise<UserOperation> {
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
});
