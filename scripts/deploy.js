async function main() {

    const [deployer] = await ethers.getSigners();

    console.log(
        "Deploying contracts with the account:",
        deployer.address
    );

    console.log("Account balance:", (await deployer.getBalance()).toString());

    const Token = await ethers.getContractFactory("Switch");
    const token = await Token.deploy();

    console.log("Token address:", token.address);

    const Vesting = await ethers.getContractFactory("Vesting");
    let vesting = await Vesting.deploy(true, token.address);

    console.log("Revocable Vesting address:", vesting.address);

    const PrivateVesting = await ethers.getContractFactory("PrivateVesting");
    const privateVesting = await PrivateVesting.deploy(true, token.address);

    console.log("Private Vesting address:", privateVesting.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });