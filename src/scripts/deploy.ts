import { ethers, network } from "hardhat";
import { Token, Vault } from "../typechain-types";
import { deployContract } from "../utils/deploy";

const { VAULT_TOKEN_NAME, VAULT_TOKEN_SYMBOL } = process.env;

async function main() {
  const [signer] = await ethers.getSigners();

  console.log(
    `starting the deployment script, will deploy multiple contracts to the network: '${network.name}', 
     with owner set to: '${signer.address}'`
  );

  const tokenContract = await deployContract<Token>(
    "Token",
    VAULT_TOKEN_NAME ?? "DEFAULT_TOKEN_NAME",
    VAULT_TOKEN_SYMBOL ?? "DEFAULT_TOKEN_SYMBOL"
  );

  await deployContract<Vault>("Vault", tokenContract);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
