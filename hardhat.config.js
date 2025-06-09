require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");
require("dotenv").config();

const {
  SEPOLIA_RPC_URL,
  HOODI_RPC_URL,
  BSC_RPC_URL,
  MONAD_RPC_URL,
  HOLESKY_RPC_URL,
  PRIVATE_KEY,
  BSC_API_KEY,
  ETHERSCAN_API_KEY,
} = process.env;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,    // <-- Enable IR compilation here to fix "stack too deep"
    },
  },
  networks: {
    // sepolia:{
    //   url : SEPOLIA_RPC_URL,
    //   accounts : [`0x${PRIVATE_KEY}`],
    // },
    holesky: {
      url: HOLESKY_RPC_URL,
      accounts: [`0x${PRIVATE_KEY}`],
    },
    // monad: {
    //   url: MONAD_RPC_URL,
    //   accounts: [`0x${PRIVATE_KEY}`],
    // },
    // bscTestnet: {
    //   url: BSC_RPC_URL,
    //   accounts: [`0x${PRIVATE_KEY}`],
    // },
    // hoodi:{
    //   url: HOODI_RPC_URL,
    //   accounts: [`0x${PRIVATE_KEY}`],
    // }
  },
  sourcify: {
    enabled: true,
  },
  etherscan: {
    apiKey: {
      holesky: ETHERSCAN_API_KEY,
    },
  },
};
