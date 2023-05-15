import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import verify from "../helper-functions"
import { networkConfig, developmentChains } from "../helper-hardhat-config"
import { ethers } from "hardhat"

const deployBox: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  // @ts-ignore
  const { getNamedAccounts, deployments, network } = hre
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  log("----------------------------------------------------")
  log("Deploying Box and waiting for confirmations...")

  log("----------------------------------------------------")
  const governor = await ethers.getContract("GovernorContract", deployer)
  const reputation = await ethers.getContract("DAOReputationToken", deployer)

  const gigNFT = await deploy("Gig", {
    from: deployer,
    args: [],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: networkConfig[hre.network.name].blockConfirmations || 1,
  })

  const whitelist = await deploy("Whitelist", {
    from: deployer,
    args: [],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: networkConfig[hre.network.name].blockConfirmations || 1,
  })

  const freelanco = await deploy("Freelanco", {
    from: deployer,
    args: [governor.address, gigNFT.address, reputation.address],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: networkConfig[hre.network.name].blockConfirmations || 1,
  })
  log(`freelanco at ${freelanco.address}`)
  // if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
  //   await verify(freelanco.address, [])
  // }
  const freelancoC = await ethers.getContractAt("Freelanco", freelanco.address)
  const timeLock = await ethers.getContract("TimeLock")
  const transferTx = await freelancoC.transferOwnership(timeLock.address)
  await transferTx.wait(1)
}

export default deployBox
deployBox.tags = ["all", "freelanco"]
