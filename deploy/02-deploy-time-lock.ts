import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import verify from "../helper-functions"
import { developmentChains, MIN_DELAY } from "../helper-hardhat-config"
import { networks } from "../networks.js";
import { ethers } from "hardhat"

const deployTimeLock: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  // @ts-expect-error
  const { getNamedAccounts, deployments, network } = hre
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  log("----------------------------------------------------")
  log("Deploying TimeLock and waiting for confirmations...")
  const timeLock = await deploy("TimeLock", {
    from: deployer,
    /**
     * Here we can set any address in admin role also zero address.
     * previously In tutorial deployer has given admin role then
     * renounced as well. in later section so we are doing the same by giving admin role to
     * deployer and then renounced to keep the tutorial same.
     */
    args: [MIN_DELAY, [], [], deployer],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: networks[network.name]?.blockConfirmations || 1,
  })
  log(`TimeLock at ${timeLock.address}`)
  
  const daoN = await ethers.getContract("DaoNFT")
  const timeLockC = await ethers.getContract("TimeLock")
  const transferTx = await daoN.transferOwnership(timeLockC.address)
  console.log("Transfered DAO NFT to Timelock..")
  await transferTx.wait(1)
}

export default deployTimeLock
deployTimeLock.tags = ["all", "timelock"]
