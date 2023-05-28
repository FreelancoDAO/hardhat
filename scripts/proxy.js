async function main() {
    const governor = await ethers.getContractFactory("GovernorContract");
    console.log("Deploying Governow, ProxyAdmin, and then Proxy...");
  
  
    const proxy = await upgrades.deployProxy(governor, ["0x326109e34C408E81C83b97bD98d3b1303701b736", "0x68389Ff6Afb354426AE438C3BBB4CCA3d8e301A0", 1, 300, 30, "0x8281Da1a776bd6cEDF7713A755094Ee30b8D940f", "0xc4F133e1067b49bb22C1D7Ec7234Fd0772741a83", "0xeA6721aC65BCeD841B8ec3fc5fEdeA6141a0aDE4"], {
      initializer: "initilize",
    });
    await proxy.deployed();
    console.log("Proxy of EMS deployed to:", proxy.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });