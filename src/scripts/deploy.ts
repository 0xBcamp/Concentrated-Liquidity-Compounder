import { ethers, network } from "hardhat";
import { ClExecutor, Narrow, Mid, Wide, Vault } from "../typechain-types";
import { deployContract } from "../utils/deploy";

const SWAP_ROUTER_ADDRESS = "0xAA23611badAFB62D37E7295A682D21960ac85A90";

async function main() {
  const [signer] = await ethers.getSigners();

  console.log(
    `starting the deployment script, will deploy multiple contracts to the network: '${network.name}', 
     with owner set to: '${signer.address}'`
  );

  const narrowContract = await deployContract<Narrow>("Narrow");
  const midContract = await deployContract<Mid>("Mid");
  const wideContract = await deployContract<Wide>("Wide");

  await deployContract<ClExecutor>("ClExecutor", SWAP_ROUTER_ADDRESS, narrowContract.target, midContract.target, wideContract.target);

  await deployContract<Vault>("Vault", midContract.target);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
