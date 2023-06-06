const { deployments, network, ethers } = require("hardhat");
const {
  // networkConfig,
  developmentChains,
} = require("../helper-hardhat-config");
require("dotenv").config();

const networkConfig = {
  default: {
    name: "hardhat",
    fee: "100000000000000000",
    keyHash:
      "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc",
    jobId: "29fa9aa13bf1468788b7cc4a500a45b8",
    fundAmount: "1000000000000000000",
    automationUpdateInterval: "30",
    subId: 1,
  },
  31337: {
    name: "localhost",
    fee: "100000000000000000",
    keyHash:
      "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc",
    jobId: "29fa9aa13bf1468788b7cc4a500a45b8",
    fundAmount: "1000000000000000000",
    automationUpdateInterval: "30",
    ethUsdPriceFeed: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
    subId: 1,
  },
  1: {
    name: "mainnet",
    linkToken: "0x514910771af9ca656af840dff83e8264ecf986ca",
    fundAmount: "0",
    automationUpdateInterval: "30",
  },
  11155111: {
    name: "sepolia",
    linkToken: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
    ethUsdPriceFeed: "0x694AA1769357215DE4FAC081bf1f309aDC325306",
    keyHash:
      "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c",
    vrfCoordinator: "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625",
    vrfWrapper: "0xab18414CD93297B0d12ac29E63Ca20f515b3DB46",
    oracle: "0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD",
    jobId: "ca98366cc7314957b8c012c72f05aeeb",
    subscriptionId: "777",
    fee: "100000000000000000",
    fundAmount: "100000000000000000", // 0.1
    automationUpdateInterval: "30",
  },
  137: {
    name: "polygon",
    linkToken: "0xb0897686c545045afc77cf20ec7a532e3120e0f1",
    ethUsdPriceFeed: "0xF9680D99D6C9589e2a93a78A04A279e509205945",
    oracle: "0x0a31078cd57d23bf9e8e8f1ba78356ca2090569e",
    jobId: "12b86114fa9e46bab3ca436f88e1a912",
    fee: "100000000000000",
    fundAmount: "100000000000000",
  },
  80001: {
    name: "mumbai",
    linkToken: "0x326C977E6efc84E512bB9C30f76E30c160eD06FB",
    ethUsdPriceFeed: "0x0715A7794a1dc8e42615F059dD6e406A6594651A",
    keyHash:
      "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f",
    vrfCoordinator: "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed",
    vrfWrapper: "0x99aFAf084eBA697E584501b8Ed2c0B37Dd136693",
    oracle: "0x40193c8518BB267228Fc409a613bDbD8eC5a97b3",
    jobId: "ca98366cc7314957b8c012c72f05aeeb",
    fee: "100000000000000000",
    fundAmount: "100000000000000000", // 0.1
    automationUpdateInterval: "30",
    subId: 1318,
  },
};

const deployGovernanceToken = async function (hre) {
  const { deployer } = await hre.getNamedAccounts();
  const BigNumber = ethers.BigNumber;
  const { deploy, log } = deployments;

  const chainId = network.config.chainId;
  const isLocalOrDevChain = developmentChains.includes(chainId);
  console.log(networkConfig[chainId]);
  const gas_limit = 500000;

  log("----------------------------------------------------");
  log("Deploying Reputation and waiting for confirmations...");

  const repotoken = await deploy("DAOReputationToken", {
    from: deployer,
    args: [],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: 1,
  });

  log(`Reputation deployed to ${repotoken.address}`);

  log("----------------------------------------------------");
  log("Deploying Mock");
  let vrfCoordinatorV2Mock, subscriptionId, vrf;
  if (isLocalOrDevChain) {
    const BASE_FEE = BigNumber.from("100000000000000000"); // 0.25 is this the premium in LINK?
    const GAS_PRICE_LINK = 1e9; // link per gas, is this the gas lane? // 0.000000001 LINK per gas

    vrf = await deploy("VRFCoordinatorV2Mock", {
      from: deployer,
      log: true,
      args: [BASE_FEE, GAS_PRICE_LINK],
    });

    log(`VRF deployed to ${vrf.address}`);

    const FUND_AMOUNT = "1000000000000000000000";
    let vrfCoordinatorV2Address, subscriptionId;

    vrfCoordinatorV2Mock = await ethers.getContract("VRFCoordinatorV2Mock");

    const transactionResponse = await vrfCoordinatorV2Mock.createSubscription();
    const transactionReceipt = await transactionResponse.wait();

    subscriptionId = transactionReceipt.events[0].args.subId;

    await vrfCoordinatorV2Mock.fundSubscription(subscriptionId, FUND_AMOUNT);
    console.log("Subscription funded", subscriptionId);
  }

  let level0 = [
    "bafkreig5txvhpsmj3ktwksbtqfuioawzpqklonkek2j67ezgrvw4hojxpm",
    "bafybeictlfowpcui42p4qe6sfjpeesj4rb6dkivhkkty4ogd6makgs7ksa",
    "bafkreiad54fkcj4xhgrllpcomxip5y3wkyg3z25lgvpln6h2imfrviqwrm",
  ];

  let level1 = [
    "bafkreiebtcekmbwdhg7izga36sr436dntjgvzuiyj3by75tzz5ecmcoqbi",
    "bafkreiakmktvhnjq4rbahitnbvvmc5yggtnlfl552bvcdk4dl63kjxkzfi",
    "bafkreifdonzpytls7kzjnllgixmc2hjkexsilualmwboxkx7wxgf5334fy",
  ];

  let level2 = [
    "bafkreibwronbp5evijccjhghclp3c6gul4qtl2mb44wajx2dbclapfphia",
    "bafkreigueabknvwxzj3xdjtbkugyieptx64dzrosdyoft5sg3tvq3hg2te",
    "bafkreich24l2kthxjhex667n6t2mlg3rjj2na6qrnqrcgpmroo5a6vqmvq",
  ];

  const whitelist = await deploy("Whitelist", {
    from: deployer,
    args: [],
    log: true,
    // we need to wait if on a live network so we can verify properly
    waitConfirmations: networkConfig[hre.network.name]?.blockConfirmations || 1,
  });

  if (isLocalOrDevChain) {
    arguments = [
      vrf.address,
      networkConfig[chainId].subId,
      networkConfig[chainId].keyHash,
      gas_limit,
      level0,
      level1,
      level2,
      repotoken.address,
      whitelist.address,
    ];
  } else {
    arguments = [
      networkConfig[chainId].vrfCoordinator,
      networkConfig[chainId].subId,
      networkConfig[chainId].keyHash,
      gas_limit,
      level0,
      level1,
      level2,
      repotoken.address,
      whitelist.address,
    ];
  }

  const daoNFT = await deploy("DaoNFT", {
    from: deployer,
    args: arguments,
    log: true,
    waitConfirmations: 1,
  });

  if (vrfCoordinatorV2Mock) {
    const tx = await vrfCoordinatorV2Mock.addConsumer(
      networkConfig[chainId].subId,
      daoNFT.address
    );
    console.log("Consumer Added", tx.address);
  } else {
    const vrfCoordinatorV2Mock = await hre.ethers.getContractAt(
      "VRFCoordinatorV2Mock",
      networkConfig[chainId].vrfCoordinator
    );
    const tx = await vrfCoordinatorV2Mock.addConsumer(
      networkConfig[chainId].subId,
      daoNFT.address
    );

    console.log("Consumer Added", tx.address);
  }
};

deployGovernanceToken.tags = ["all", "reputationtoken"];
module.exports = deployGovernanceToken;
