const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with:", deployer.address);

  // Deploy Token A
  const Token = await hre.ethers.getContractFactory("ERC20Token");
  const tokenA = await Token.deploy("TokenA", "ATKN", 1000000);
  await tokenA.waitForDeployment();
  console.log("TokenA deployed at:", await tokenA.getAddress());

  // Deploy Token B
  const tokenB = await Token.deploy("TokenB", "BTKN", 1000000);
  await tokenB.waitForDeployment();
  console.log("TokenB deployed at:", await tokenB.getAddress());

  // Deploy WETH
  const WETH = await hre.ethers.getContractFactory("WETH");
  const weth = await WETH.deploy();
  await weth.waitForDeployment();
  console.log("WETH deployed at:", await weth.getAddress());

  // Deploy DEXFactory
  const DEXFactory = await hre.ethers.getContractFactory("DEXFactory");
  const factory = await DEXFactory.deploy();
  await factory.waitForDeployment();
  console.log("DEXFactory deployed at:", await factory.getAddress());

  // Deploy DEXRouter
  const DEXRouter = await hre.ethers.getContractFactory("DEXRouter");
  const router = await DEXRouter.deploy(await factory.getAddress(), await weth.getAddress());
  await router.waitForDeployment();
  console.log("DEXRouter deployed at:", await router.getAddress());

  // Create pair via Factory
  const tx = await factory.createPair(await tokenA.getAddress(), await tokenB.getAddress());
  const receipt = await tx.wait();
  const pairCreatedEvent = receipt.logs.find(
    (log) => log.fragment.name === "PairCreated"
  );

  const pairAddress = pairCreatedEvent.args.pair;
  console.log(`DEXPair deployed at: ${pairAddress}`);

  // Approve router to spend tokens
  const amount = hre.ethers.parseUnits("10000");
  await tokenA.approve(await router.getAddress(), amount);
  await tokenB.approve(await router.getAddress(), amount);
  
}

main().catch((error) => {
  console.error("Error in deployment:", error);
  process.exit(1);
});
