import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const { OPT_MAINNET_ALCHEMY_API_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.21",
      },
    ],
  },
  networks: {
    hardhat: {
      chainId: 10,
      forking: {
        enabled: false, //set to 'false' when API KEY env var is not set
        url: `https://opt-mainnet.g.alchemy.com/v2/${OPT_MAINNET_ALCHEMY_API_KEY}`,
      },
    },
  },
};

export default config;
