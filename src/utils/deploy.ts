import { ethers } from "hardhat";

export async function deployContract<BaseContract>(
  name: string,
  ...ctorArguments: any
): Promise<BaseContract> {
  console.log(
    `deploying ${name} contract with constructor arguments: ${ctorArguments}`
  );

  const contractFactory = await ethers.getContractFactory(name);
  const contract = await contractFactory.deploy(...ctorArguments);

  const deployedContract = (await contract.waitForDeployment()) as BaseContract;

  const address = await contract.getAddress();
  console.log(
    `contract with name: '${name}' was deployed to address: '${address}'`
  );

  return deployedContract;
}
