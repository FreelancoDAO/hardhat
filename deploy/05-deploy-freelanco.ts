import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import verify from "../helper-functions";
import { networks as networkConfig } from "../networks.js";
import { ethers } from "hardhat";

const deployBox: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  // @ts-expect-error
  const { getNamedAccounts, deployments, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  log("----------------------------------------------------");
  log("Deploying Box and waiting for confirmations...");

  log("----------------------------------------------------");
  const governor = await ethers.getContract("GovernorContract", deployer);
  const reputation = await ethers.getContract("DAOReputationToken", deployer);

  const gigNFT = await deploy("Gig", {
    from: deployer,
    args: [],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: networkConfig[hre.network.name]?.blockConfirmations || 1,
  });

  const whitelist = await deploy("Whitelist", {
    from: deployer,
    args: [],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: networkConfig[hre.network.name]?.blockConfirmations || 1,
  });

  const freelanco = await deploy("Freelanco", {
    from: deployer,
    args: [governor.address, gigNFT.address, reputation.address],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: networkConfig[hre.network.name]?.blockConfirmations || 1,
  });
  log(`freelanco at ${freelanco.address}`);
  const freelancoC = await ethers.getContractAt("Freelanco", freelanco.address);
  const timeLock = await ethers.getContract("TimeLock");
  const transferTx = await freelancoC.transferOwnership(timeLock.address);
  await transferTx.wait(1);

  const daoNFT = await ethers.getContract("DaoNFT");
  const repo = await ethers.getContract("DAOReputationToken");

  await governor.setDAOContracts(freelanco.address, daoNFT.address);
};

export default deployBox;
deployBox.tags = ["all", "freelanco"];
