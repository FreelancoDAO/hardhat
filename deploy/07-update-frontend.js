const fs = require("fs")
const { network } = require("hardhat")
const { addressFile, abiFile } = require("../../hardhat/helper-hardhat-config")

const frontEndContractsFile = "../frontend/constants/addresses.json"
const frontEndAbiFile = "../frontend/constants/"

module.exports = async () => {
  console.log("Writing to front end...")
  await updateContractAddresses("Gig")
  await updateContractAddresses("Freelanco")
  await updateContractAddresses("DaoNFT")
  await updateContractAddresses("GovernorContract")
  await updateContractAddresses("Whitelist")
  await updateAbi("Gig")
  await updateAbi("Freelanco")
  await updateAbi("DaoNFT")
  await updateAbi("GovernorContract")
  await updateAbi("Whitelist")
  console.log("Front end written!")
}

async function updateAbi(contractName) {
  const raffle = await ethers.getContract(contractName)
  console.log(frontEndAbiFile)
  fs.writeFileSync(
    frontEndAbiFile + contractName + ".json",
    raffle.interface.format(ethers.utils.FormatTypes.json)
  )
}

async function updateContractAddresses(contractName) {
  const raffle = await ethers.getContract(contractName)
  console.log(frontEndContractsFile)
  const contractAddresses = JSON.parse(fs.readFileSync(frontEndContractsFile, "utf8"))
  if (network.config.chainId.toString() in contractAddresses[contractName]) {
    if (
      !contractAddresses[contractName][network.config.chainId.toString()].includes(raffle.address)
    ) {
      contractAddresses[contractName][network.config.chainId.toString()].push(raffle.address)
    }
  } else {
    contractAddresses[contractName][network.config.chainId.toString()] = [raffle.address]
  }
  fs.writeFileSync(frontEndContractsFile, JSON.stringify(contractAddresses))
}
module.exports.tags = ["all", "frontend"]
