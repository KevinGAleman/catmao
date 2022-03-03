const hre = require("hardhat");

async function main() {
    const Relevanksy = await hre.ethers.getContractFactory("Relevanksy");
    const relevanksyFactory = await Relevanksy.deploy();
    await relevanksyFactory.deployed();

    console.log("Relevanksy is deployed to address: ", relevanksyFactory.address)

    const [deployer] = await hre.ethers.getSigners();
    const accountBalance = await deployer.getBalance();

    console.log("Deploying contracts with account: ", deployer.address);
    console.log("Account balance: ", accountBalance.toString());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });