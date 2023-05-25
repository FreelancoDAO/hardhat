const fs = require("fs").promises;
const path = require("path");
import {
  GovernorContract,
  GovernanceToken,
  TimeLock,
  Freelanco,
  DaoNFT,
  VRFConsumerBaseV2,
  VRFCoordinatorV2Mock,
} from "../../typechain-types";
import { deployments, ethers, network } from "hardhat";
import { assert, expect } from "chai";
import {
  FUNC,
  PROPOSAL_DESCRIPTION,
  NEW_STORE_VALUE,
  VOTING_DELAY,
  VOTING_PERIOD,
  MIN_DELAY,
} from "../../helper-hardhat-config";
import { moveBlocks } from "../../utils/move-blocks";
import { moveTime } from "../../utils/move-time";

const {
  simulateRequest,
  buildRequest,
  getDecodedResultLog,
  getRequestConfig,
} = require("../../FunctionsSandboxLibrary");

describe("Governor Flow", async () => {
  let governor: GovernorContract;
  let governanceToken: GovernanceToken;
  let timeLock: TimeLock;
  let freelanco: Freelanco;
  let daoNft: DaoNFT;
  let vrf: VRFCoordinatorV2Mock;
  const voteWay = 1; // for
  const reason = "I lika do da cha cha";
  beforeEach(async () => {
    await deployments.fixture(["all"]);
    governor = await ethers.getContract("GovernorContract");
    timeLock = await ethers.getContract("TimeLock");
    governanceToken = await ethers.getContract("GovernanceToken");
    freelanco = await ethers.getContract("Freelanco");
    vrf = await ethers.getContract("VRFCoordinatorV2Mock");

    // daoNft = await ethers.getContract("DaoNFT")
  });

  it("can only be changed through governance", async () => {
    const [freelancer, client] = await ethers.getSigners();
    await expect(
      freelanco.handleDispute(await freelanco.getOfferId(1), freelancer.address)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("sends offer, approves offer, then disputes i.e proposes, votes, waits, queues, and then executes", async () => {
    const [freelancer, client] = await ethers.getSigners();
    // console.log("Freelancer: ", freelancer)

    await freelanco
      .connect(client)
      .sendOffer(0, freelancer.address, "Terms are to dispute it", 100, {
        value: ethers.utils.parseEther("200"),
      });

    const offerId = await freelanco.getOfferId(1);
    await freelanco.connect(freelancer).approveOffer(offerId);

    //client making the dispute
    const tx = await freelanco
      .connect(client)
      .disputeContract(offerId, "I was told to do so!");
    const receipt = await tx.wait(1);
    // console.log(BigInt(receipt.events![0].args![4]._hex))

    const dispute = await freelanco.getDispute(1);

    const targets = dispute.targets;
    const calldata = dispute.calldatas;
    const PROPOSAL_DESCRIPTION = dispute.description;

    console.log("Targets:", targets);

    const proposalId = BigInt(dispute.proposalId._hex);

    // const proposeReceipt = await proposeTx.wait(1)
    // const proposalId = proposeReceipt.events![0].args!.proposalId
    let proposalState = await governor.state(proposalId);

    await moveBlocks(VOTING_DELAY + 1);
    // vote
    console.log("Voting..");
    const daoNft = await ethers.getContract("DaoNFT");

    console.log("Buying NFT");
    const txRsponse = await daoNft.requestNft({
      value: ethers.utils.parseEther("2"),
    });

    const transactionReceipt = await txRsponse.wait();

    // console.log(transactionReceipt.events[1])
    const requestId = transactionReceipt.events[1].args.requestId;

    //Pretent to be VRF
    // simulate callback from the oracle network
    await expect(vrf.fulfillRandomWords(requestId, daoNft.address)).to.emit(
      daoNft,
      "NftMinted"
    );

    console.log("VRF sent a random number");

    const voteTx = await governor.castVoteWithReason(
      proposalId,
      voteWay,
      reason
    );
    await voteTx.wait(1);

    //simulate chat gpt voting

    console.log("Vote casted from account: ", freelancer.address);
    console.log("Simulating CHAT GPT");

    const balance2ETH3 = await ethers.provider.getBalance(freelanco.address);
    console.log("Balance: ", BigInt(balance2ETH3._hex));

    try {
      const taskArgs = {};
      const unvalidatedRequestConfig = require("/Users/shivamarora/Documents/Projects/freelanco-dao/deployment/hardhat/Functions-request-config.js");
      const requestConfig = getRequestConfig(unvalidatedRequestConfig);
      // Fetch the mock DON public key
      const oracle = await ethers.getContractAt(
        "FunctionsOracle",
        "0x0B306BF915C4d645ff596e518fAf3F9669b97016"
      );
      const DONPublicKey = await oracle.getDONPublicKey();
      // Remove the preceding 0x from the DON public key
      requestConfig.DONPublicKey = DONPublicKey.slice(2);
      const request = await buildRequest(requestConfig);

      const source = await fs.readFile("./API-request-example.js", "utf8");

      const requestTx = await governor.executeRequest(
        request.source,
        request.secrets ?? [],
        request.args ?? [], // Chainlink Functions request args
        1, // Subscription ID
        300000, // Gas limit for the transaction
        proposalId
      );

      const requestTxReceiptChainlink = await requestTx.wait(1);
      // console.log(requestTxReceiptChainlink);
      const requestId2 = requestTxReceiptChainlink.events[2].args.id;
      const requestGasUsed = requestTxReceiptChainlink.gasUsed.toString();

      console.log("Request gas used", requestGasUsed);

      const { success, result, resultLog } = await simulateRequest(
        requestConfig
      );
      console.log(`\n${resultLog}`);

      const registry = await ethers.getContractAt(
        "FunctionsBillingRegistry",
        "0x68B1D87F95878fE05B998F19b66F4baba5De1aed"
      );

      console.log("RESGIRErY", registry.address);
      const accounts = await ethers.getSigners();
      const dummyTransmitter = accounts[0].address;
      const dummySigners = Array(31).fill(dummyTransmitter);
      const fulfillTx = await registry.fulfillAndBill(
        requestId2,
        success ? result : "0x",
        success ? "0x" : result,
        dummyTransmitter,
        dummySigners,
        4,
        100_000,
        500_000,
        {
          gasLimit: 500_000,
        }
      );
      await fulfillTx.wait(1);
    } catch (fulfillError) {
      // Catch & report any unexpected fulfillment errors
      console.log(
        "\nUnexpected error encountered when calling fulfillRequest in client contract."
      );
      console.log(fulfillError);
    }

    proposalState = await governor.state(proposalId);
    console.log("Before Voting Period State:", proposalState);
    // assert.equal(proposalState.toString(), "1");

    await moveBlocks(VOTING_PERIOD + 1);

    // queue & execute
    // proposalState = await governor.state(proposalId);
    // console.log("STATE:", proposalState);

    // try {
    //   console.log("Queing...");
    //   const descriptionHash = ethers.utils.keccak256(
    //     ethers.utils.toUtf8Bytes(PROPOSAL_DESCRIPTION)
    //   );
    //   // const descriptionHash = ethers.utils.id(PROPOSAL_DESCRIPTION)
    //   const queueTx = await governor.queue(
    //     targets,
    //     [0, 0],
    //     calldata,
    //     descriptionHash
    //   );
    //   await queueTx.wait(1);
    //   await moveTime(MIN_DELAY + 2);
    //   await moveBlocks(10);

    //   proposalState = await governor.state(proposalId);
    //   console.log("STATE:", proposalState);

    //   console.log("Executing...");
    //   const exTx = await governor.execute(
    //     targets,
    //     [0, 0],
    //     calldata,
    //     descriptionHash
    //   );
    //   await exTx.wait(1);
    // } catch (e) {
    //   console.log("Queuening and Executing Failed", e);
    // }

    await moveBlocks(20);
    proposalState = await governor.state(proposalId);
    console.log("STATE:", proposalState);

    const balance0ETH = await ethers.provider.getBalance(freelanco.address);
    console.log("Balance: ", BigInt(balance0ETH._hex));

    // await freelanco.connect(freelancer).getDisputedFunds(1);
    // await moveBlocks(5);

    const balance2ETH = await ethers.provider.getBalance(freelanco.address);
    console.log("Balance: ", BigInt(balance2ETH._hex));
  });
});
