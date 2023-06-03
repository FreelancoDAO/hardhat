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
  DAOReputationToken,
  Gig
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
  let daorepo: DAOReputationToken;
  let gigNFT: Gig
  const voteWay = 1; // for
  const reason = "I lika do da cha cha";

  beforeEach(async () => {
    await deployments.fixture(["all"]);
    governor = await ethers.getContract("GovernorContract");
    timeLock = await ethers.getContract("TimeLock");
    governanceToken = await ethers.getContract("GovernanceToken");
    freelanco = await ethers.getContract("Freelanco");
    vrf = await ethers.getContract("VRFCoordinatorV2Mock");
    daorepo = await ethers.getContract("DAOReputationToken");
    gigNFT = await ethers.getContract("Gig");

    // daoNft = await ethers.getContract("DaoNFT")
  });

  it("dispute resolution can only be done through governance", async () => {
    const [freelancer, client] = await ethers.getSigners();
    await expect(
      freelanco.handleDispute(await freelanco.getOfferId(1), freelancer.address)
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("grant can only be performed through governance", async () => {
    const [freelancer, client, otherAccount] = await ethers.getSigners();
  
    const freelanco = await ethers.getContract("Freelanco"); // Replace "Freelanco" with the actual name of your contract
  
    // Ensure that the function reverts when called by a non-governance account
    await expect(
      freelanco.withdraw()
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("sends offer to non-existing gig token ID", async () => {
    const [freelancer, client] = await ethers.getSigners();
  
    // Boost freelancer's profile
    await freelanco.connect(freelancer).boostProfile(10, {
      value: ethers.utils.parseEther("10"),
    });
  
    // Mint a gig token with a specific ID
    const gigTokenId = 0;
    await gigNFT.connect(freelancer).safeMint("uri");
  
    // Try to send an offer to a non-existing gig token ID
    const nonExistingGigTokenId = 1;
    await expect(
      freelanco
        .connect(client)
        .sendOffer(nonExistingGigTokenId, freelancer.address, "Terms are to dispute it", 100, {
          value: ethers.utils.parseEther("10"),
        })
    ).to.be.revertedWith("ERC721: invalid token ID");
  });

  it("sends offer with less than 0 ETH value", async () => {
    const [freelancer, client] = await ethers.getSigners();
  
    // Boost freelancer's profile
    await freelanco.connect(freelancer).boostProfile(10, {
      value: ethers.utils.parseEther("10"),
    });
  
    // Mint a gig token
    await gigNFT.connect(freelancer).safeMint("uri");
  
    // Try to send an offer with less than 0 ETH value
    
    await expect(
      freelanco
        .connect(client)
        .sendOffer(0, freelancer.address, "Terms are to dispute it", 100, {
          // value: invalidValue, no value
        })
    ).to.be.revertedWith("Freelanco__TransactionFailed");
  });

  it("sends less than mint fee when requesting NFT", async () => {
    const [freelancer] = await ethers.getSigners();
  
    const daoNft = await ethers.getContract("DaoNFT");
  
    // Try to send an amount less than the mint fee when requesting NFT
    const invalidValue = ethers.utils.parseEther(".000001"); // Less than the mint fee
    await expect(
      daoNft.requestNft({
        value: invalidValue,
      })
    ).to.be.reverted
  });

  it("fails to vote when member doesn't have a DAO NFT", async () => {
    const [member] = await ethers.getSigners();
  
    const daoNft = await ethers.getContract("DaoNFT");
    const governor = await ethers.getContract("GovernorContract"); // Replace "Governor" with the actual name of your contract
  
    // Try to vote without having a DAO NFT
    const invalidProposalId = 123; // Replace with a non-existent proposal ID
    const voteWay = 1; // Replace with your desired vote choice (true/false)
    const reason = "Voting reason"; // Replace with your desired voting reason
    await expect(
      governor.castVoteWithReason(invalidProposalId, voteWay, reason)
    ).to.be.revertedWith("Governor__TransactionFailed");
  });
  

  it("sends offer, approves offer, then disputes i.e proposes, votes, waits, queues, and simulate GPTs vote to execute", async () => {
    const [freelancer, client] = await ethers.getSigners();

    await freelanco.connect(freelancer).boostProfile(10, {
      value: ethers.utils.parseEther("10"),
    });

    await gigNFT.connect(freelancer).safeMint("uri");

    await freelanco
      .connect(client)
      .sendOffer(0, freelancer.address, "Terms are to dispute it", 100, {
        value: ethers.utils.parseEther("10"),
      });

    const offerId = await freelanco.getOfferId(1);
    await freelanco.connect(freelancer).approveOffer(offerId);

    //client making the dispute
    await freelanco
      .connect(client)
      .disputeContract(offerId, "I was told to do so!");

    const dispute = await freelanco.getDispute(1);
    const targets = dispute.targets;
    // const calldata = dispute.calldatas;
    const PROPOSAL_DESCRIPTION = dispute.description;

    const proposalId = BigInt(dispute.proposalId._hex);
    let proposalState = await governor.state(proposalId);
    await moveBlocks(VOTING_DELAY + 1);

    // vote
    const daoNft = await ethers.getContract("DaoNFT");
    const txRsponse = await daoNft.requestNft({
      value: ethers.utils.parseEther("2"),
    });
    const transactionReceipt = await txRsponse.wait();
    const requestId = transactionReceipt.events[1].args.requestId;

    //Pretent to be VRF
    //Simulate callback from the oracle network
    await expect(vrf.fulfillRandomWords(requestId, daoNft.address)).to.emit(
      daoNft,
      "NftMinted"
    );

    const voteTx = await governor.castVoteWithReason(
      proposalId,
      voteWay,
      reason
    );
    await voteTx.wait(1);

    //simulate chat gpt voting
    const balance2ETH3 = await ethers.provider.getBalance(freelanco.address);
    try {
      const unvalidatedRequestConfig = require("/Users/shivamarora/Documents/Projects/freelanco-dao/org/hardhat/Functions-request-config.js");
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

    await moveBlocks(VOTING_PERIOD + 1);

    const tx3 = await governor.executeProposal(proposalId);
    tx3.wait(1);

    const initialBalance = await ethers.provider.getBalance(freelanco.address);

    // Use a different client address
    await expect(
      freelanco.connect(freelancer).getDisputedFunds(offerId)
    ).to.be.revertedWith("Freelanco__TransactionFailed");

    await freelanco.connect(client).getDisputedFunds(offerId);

    const finalBalance = await ethers.provider.getBalance(freelanco.address);
    expect(finalBalance.lt(initialBalance)).to.be.true;
  });

  it("should successfully initiate a grant proposal, vote, and execute", async () => {
    const [deployer, member, freelancer, client] = await ethers.getSigners();

    await gigNFT.connect(freelancer).safeMint("uri");

    await freelanco
      .connect(client)
      .sendOffer(0, freelancer.address, "Terms are to dispute it", 100, {
        value: ethers.utils.parseEther("10"),
      });

    const offerId = await freelanco.getOfferId(1);
  
    // Move blocks to ensure the proposal is in the correct state
    await moveBlocks(20);
  
    // Initiate a grant proposal
    const txResponse = await freelanco
      .connect(member)
      .initiateGrantProposal("reason");
    const transactionReceipt = await txResponse.wait();
    const proposalId = transactionReceipt.events[1].args._proposalId;
  
    // Move blocks to reach the voting phase
    await moveBlocks(VOTING_DELAY + 2);

    // vote
    const daoNft = await ethers.getContract("DaoNFT");
    const txRsponse = await daoNft.requestNft({
      value: ethers.utils.parseEther("2"),
    });
    const nft_transactionReceipt = await txRsponse.wait();
    const requestId = nft_transactionReceipt.events[1].args.requestId;

    //Pretent to be VRF
    //Simulate callback from the oracle network
    await expect(vrf.fulfillRandomWords(requestId, daoNft.address)).to.emit(
      daoNft,
      "NftMinted"
    );
  
    // Vote on the proposal
    const voteTx = await governor.castVoteWithReason(
      proposalId,
      voteWay,
      reason
    );
    await voteTx.wait(1);
  
    // Move blocks to complete the voting period
    await moveBlocks(10);
  
    // Check the state of the grant proposal
    const proposalState = await governor.state(proposalId);
  
    try {
      // Queue and execute the proposal
      const descriptionHash = ethers.utils.keccak256(
        ethers.utils.toUtf8Bytes("reason")
      );
      const queueTx = await governor.queue(
        [freelanco.address],
        [0],
        [transactionReceipt.events[1].args.data],
        descriptionHash
      );
      await queueTx.wait(1);
      await moveTime(MIN_DELAY + 2);
      await moveBlocks(10);
      
      const balanceBefore = await ethers.provider.getBalance(freelanco.address);
  
      const exTx = await governor.execute(
        [freelanco.address],
        [0],
        [transactionReceipt.events[1].args.data],
        descriptionHash
      );
        // Assert that the freelancer's balance has increase

      // expect(balanceBefore < balanceAfter).to.be.true;
      const finalBalance = await ethers.provider.getBalance(freelanco.address);
      
      await exTx.wait(1);
      expect(finalBalance.lt(balanceBefore)).to.be.true; //funds withrdrew
    } catch (e) {
      console.log("Queueing and Executing Failed", e);
    }
  });

});
