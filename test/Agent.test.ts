import { EntryPoint, EntryPoint__factory } from "@account-abstraction/contracts";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { Signer, Wallet } from "ethers";
import { arrayify, keccak256, solidityPack } from "ethers/lib/utils";
import { ethers, network } from "hardhat";
import { take } from "lodash";
import {
  Account,
  AgentAccessControl,
  AgentAccessControl__factory,
  AgentAccountFactory,
  AgentAccountFactory__factory,
  TicTacToe,
  TicTacToe__factory,
} from "../types";
import { Account__factory } from "../types/factories/contracts/Agent";
import { ONE_ETH } from "./constants";
import { estimateGas, fillUserOPDefaults, signUserOp } from "./userOpUtils";
import { revertToSnapShot, takeSnapshot } from "./utils";

describe("TicTacToe Test", () => {
  let signers: Signer[];
  let deployer: Signer;
  let ticTacToe: TicTacToe;
  let player1: Signer;
  let player1Address: string;
  let player2: Signer;
  let player2Address: string;
  let avatar: Wallet;
  let agent: Wallet;
  let snapshotId: string;

  let scWallet: Account;
  let accountFactory: AgentAccountFactory;
  let entryPoint: EntryPoint;
  let accessModule: AgentAccessControl;

  before(async () => {
    signers = await ethers.getSigners();
    [deployer, player1, player2] = take(signers, 3);
    player1Address = await player1.getAddress();
    player2Address = await player2.getAddress();
    ticTacToe = await new TicTacToe__factory(deployer).deploy();

    avatar = new Wallet(Wallet.createRandom().privateKey, ethers.provider);
    agent = new Wallet(Wallet.createRandom().privateKey, ethers.provider);
    await deployer.sendTransaction({
      to: avatar.address,
      value: ONE_ETH,
    });
    await deployer.sendTransaction({
      to: agent.address,
      value: ONE_ETH,
    });

    entryPoint = await new EntryPoint__factory(deployer).deploy();
    accountFactory = await new AgentAccountFactory__factory(deployer).deploy(entryPoint.address);
    scWallet = (await createAccount(deployer, avatar.address, accountFactory)).proxy;
    scWallet.addDeposit({ value: ONE_ETH });

    accessModule = await new AgentAccessControl__factory(deployer).deploy(agent.address, scWallet.address);
    await accessModule.connect(agent).setValidFunction("createNewGame(address,address)", true);

    let messageHash = solidityPack(["address"], [accessModule.address]);
    messageHash = keccak256(messageHash);
    const signedMsg = await avatar.signMessage(arrayify(messageHash));
    await scWallet.setAccessControl(accessModule.address, signedMsg);
  });

  beforeEach(async () => {
    snapshotId = await takeSnapshot();
  });

  afterEach(async () => {
    await revertToSnapShot(snapshotId);
  });

  it("Normal Call TicTacToe", async () => {
    await ticTacToe.connect(deployer).createNewGame(player1Address, player2Address);
  });

  it("Direct Call Case", async () => {
    // GameID: 0; Player1: scPlayer; Player2: player2
    const execCreateGame = ticTacToe.interface.encodeFunctionData("createNewGame", [player1Address, player2Address]);
    await scWallet.connect(agent).execute(ticTacToe.address, 0, execCreateGame);
    const newGameEvent = (await ticTacToe.queryFilter(ticTacToe.filters.NewGame()))[0];
    const newGameId = newGameEvent.args.gameId;
    expect(newGameId).to.be.eq(0);
  });

  it("Exceptional Case in direct call: Wrong caller", async () => {
    const execCreateGame = ticTacToe.interface.encodeFunctionData("createNewGame", [player1Address, player2Address]);
    await expect(scWallet.connect(player1).execute(ticTacToe.address, 0, execCreateGame)).to.be.rejectedWith(
      "Account: Not authorized call",
    );
  });

  it("Exceptional Case in direct call: Wrong function", async () => {
    const execMove = ticTacToe.interface.encodeFunctionData("makeMove", [3, 0]);
    await expect(scWallet.connect(agent).execute(ticTacToe.address, 0, execMove)).to.be.rejectedWith(
      "Account: Not authorized call",
    );
  });

  it("UserOperation Call Case", async () => {
    let userOp = fillUserOPDefaults({ sender: scWallet.address });
    userOp.nonce = (await scWallet.getNonce()).toNumber();
    const execCreateGame = ticTacToe.interface.encodeFunctionData("createNewGame", [player1Address, player2Address]);
    userOp.callData = scWallet.interface.encodeFunctionData("execute", [ticTacToe.address, 0, execCreateGame]);
    userOp = await estimateGas(userOp, entryPoint.address);
    const chainId = network.config.chainId ?? 0;
    userOp = signUserOp(userOp, agent, entryPoint.address, chainId);

    const createTx = await entryPoint.connect(deployer).handleOps([userOp], await deployer.getAddress());
    const createReceipt = await ethers.provider.getTransactionReceipt(createTx.hash);
    console.log("create new game with access module via userOp: ", createReceipt.gasUsed.toString());
  });

  it("Exceptional Case in userOp call: Wrong function", async () => {
    await ticTacToe.connect(deployer).createNewGame(scWallet.address, player2Address);
    let userOp = fillUserOPDefaults({ sender: scWallet.address });
    userOp.nonce = (await scWallet.getNonce()).toNumber();
    const execMove = ticTacToe.interface.encodeFunctionData("makeMove", [3, 0]);
    userOp.callData = scWallet.interface.encodeFunctionData("execute", [ticTacToe.address, 0, execMove]);
    userOp = await estimateGas(userOp, entryPoint.address);
    const chainId = network.config.chainId ?? 0;
    userOp = signUserOp(userOp, agent, entryPoint.address, chainId);

    await expect(entryPoint.connect(deployer).simulateValidation(userOp))
      .to.be.revertedWithCustomError(entryPoint, "ValidationResult")
      // the args in the next line are not all important, we only want to check the boolean var is what we expect.
      // Since we cannot find a specific placeholder for this case, we directly use the real value for all vars except the boolean var.
      .withArgs([79957, 0, true, 0, 281474976710655, "0x"], anyValue, anyValue, anyValue);
  });

  async function createAccount(
    deployer: Signer,
    avatarAddr: string,
    factory: AgentAccountFactory,
  ): Promise<{ proxy: Account; accountImp: string }> {
    const accountImp = await factory.accountImp();
    await factory.createAccount(avatarAddr, 0);
    const accountAddr = await factory.getAddress(avatarAddr, 0);
    const proxy = Account__factory.connect(accountAddr, deployer);
    return {
      proxy,
      accountImp,
    };
  }
});
