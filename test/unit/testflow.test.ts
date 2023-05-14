import {
  GovernorContract,
  GovernanceToken,
  TimeLock,
  Freelanco,
  DaoNFT,
  VRFConsumerBaseV2,
  VRFCoordinatorV2Mock,
} from "../../typechain-types"
import { deployments, ethers, network } from "hardhat"
import { assert, expect } from "chai"
import {
  FUNC,
  PROPOSAL_DESCRIPTION,
  NEW_STORE_VALUE,
  VOTING_DELAY,
  VOTING_PERIOD,
  MIN_DELAY,
} from "../../helper-hardhat-config"
import { moveBlocks } from "../../utils/move-blocks"
import { moveTime } from "../../utils/move-time"

describe("Governor Flow", async () => {
  let governor: GovernorContract
  let governanceToken: GovernanceToken
  let timeLock: TimeLock
  let freelanco: Freelanco
  let daoNft: DaoNFT
  let vrf: VRFCoordinatorV2Mock
  const voteWay = 1 // for
  const reason = "I lika do da cha cha"
  beforeEach(async () => {
    await deployments.fixture(["all"])
    governor = await ethers.getContract("GovernorContract")
    timeLock = await ethers.getContract("TimeLock")
    governanceToken = await ethers.getContract("GovernanceToken")
    freelanco = await ethers.getContract("Freelanco")
    vrf = await ethers.getContract("VRFCoordinatorV2Mock")
    // daoNft = await ethers.getContract("DaoNFT")
  })

  it("can only be changed through governance", async () => {
    const [freelancer, client] = await ethers.getSigners()
    await expect(
      freelanco.handleDispute(await freelanco.getOfferId(1), freelancer.address)
    ).to.be.revertedWith("Ownable: caller is not the owner")
  })

  it("sends offer, approves offer, then disputes i.e proposes, votes, waits, queues, and then executes", async () => {
    const [freelancer, client] = await ethers.getSigners()
    // console.log("Freelancer: ", freelancer)

    await freelanco
      .connect(client)
      .sendOffer(0, freelancer.address, "Terms are to dispute it", 100, {
        value: ethers.utils.parseEther("100"),
      })

    const offerId = await freelanco.getOfferId(1)
    await freelanco.connect(freelancer).approveOffer(offerId)

    const tx = await freelanco.connect(client).disputeContract(offerId, "I was told to do so!")
    const receipt = await tx.wait(1)
    // console.log(BigInt(receipt.events![0].args![4]._hex))

    const dispute = await freelanco.getDispute(1)

    const targets = dispute.targets
    const calldata = dispute.calldatas
    const PROPOSAL_DESCRIPTION = dispute.description

    const proposalId = BigInt(dispute.proposalId._hex)

    // const proposeReceipt = await proposeTx.wait(1)
    // const proposalId = proposeReceipt.events![0].args!.proposalId
    let proposalState = await governor.state(proposalId)

    await moveBlocks(VOTING_DELAY + 1)
    // vote
    console.log("Voting..")
    const daoNft = await ethers.getContract("DaoNFT")

    console.log("Buying NFT")
    const txRsponse = await daoNft.requestNft({ value: ethers.utils.parseEther("1") })

    const transactionReceipt = await txRsponse.wait()

    // console.log(transactionReceipt.events[1])
    const requestId = transactionReceipt.events[1].args.requestId

    //Pretent to be VRF
    // simulate callback from the oracle network
    await expect(vrf.fulfillRandomWords(requestId, daoNft.address)).to.emit(daoNft, "NftMinted")

    console.log("VRF sent a random number")

    const voteTx = await governor.castVoteWithReason(proposalId, voteWay, reason)
    await voteTx.wait(1)
    proposalState = await governor.state(proposalId)
    assert.equal(proposalState.toString(), "1")

    await moveBlocks(VOTING_PERIOD + 1)

    // queue & execute
    proposalState = await governor.state(proposalId)
    console.log("STATE:", proposalState)

    console.log("Queing...")
    const descriptionHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(PROPOSAL_DESCRIPTION))
    // const descriptionHash = ethers.utils.id(PROPOSAL_DESCRIPTION)
    const queueTx = await governor.queue(targets, [0], calldata, descriptionHash)
    await queueTx.wait(1)
    await moveTime(MIN_DELAY + 1)
    await moveBlocks(1)

    proposalState = await governor.state(proposalId)
    console.log("STATE:", proposalState)

    console.log("Executing...")
    const exTx = await governor.execute(targets, [0], calldata, descriptionHash)
    await exTx.wait(1)
  })
})
