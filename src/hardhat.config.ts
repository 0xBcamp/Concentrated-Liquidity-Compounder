import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";
import * as crypto from "crypto";

const { ARB_MAINNET_ALCHEMY_URL, PRIVATE_KEY, PRIVATE_KEY_1 } = process.env;

const DEFAULT_COMPILER_SETTINGS = {
  version: "0.8.21",
  settings: {
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 1_000_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const LOW_OPTIMIZER_COMPILER_SETTINGS = {
  version: "0.8.21",
  settings: {
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 2_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const LOWEST_OPTIMIZER_COMPILER_SETTINGS = {
  version: "0.8.21",
  settings: {
    evmVersion: 'istanbul',
    optimizer: {
      enabled: true,
      runs: 1_000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [DEFAULT_COMPILER_SETTINGS],
  },
  // overrides: {
  //   'contracts/NonfungiblePositionManager.sol': LOW_OPTIMIZER_COMPILER_SETTINGS,
  //   'contracts/test/MockTimeNonfungiblePositionManager.sol': LOW_OPTIMIZER_COMPILER_SETTINGS,
  //   'contracts/test/NFTDescriptorTest.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
  //   'contracts/NonfungibleTokenPositionDescriptor.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
  //   'contracts/libraries/NFTDescriptor.sol': LOWEST_OPTIMIZER_COMPILER_SETTINGS,
  // },
  defaultNetwork: "hardhat",
  mocha: {
    timeout: 100 * 1000,
  },
  networks: {
    hardhat: {
      chainId: 42161,
      forking: {
        enabled: true, //set to 'false' when API KEY env var is not set
        url: `${ARB_MAINNET_ALCHEMY_URL}`,
      },
      accounts: [
        {
          privateKey: `0x${fetchEthAccountPrivateKey(
            PRIVATE_KEY
          )}`,
          balance: "9999999999999999999999999999",
        },
        {
          privateKey: `0x${fetchEthAccountPrivateKey(
            PRIVATE_KEY_1
          )}`,
          balance: "9999999999999999999999999999",
        },
      ],
    },
  },

};

function fetchEthAccountPrivateKey(pvtKeyEnvVar: string | undefined): string {
  console.log(pvtKeyEnvVar);
  if (pvtKeyEnvVar) {
    console.log("private key was set as environment variable");
    return pvtKeyEnvVar;
  }
  console.log(
    "private key was not set as environment variable. Generating mocked private key"
  );
  return generateMockedPvtKey();
}

function generateMockedPvtKey(): string {
  return crypto.randomBytes(32).toString("hex");
}


export default config;
