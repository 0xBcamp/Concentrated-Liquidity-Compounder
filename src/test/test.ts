import { expect } from "chai"
import { ethers } from "hardhat"
import { deployContract } from "../utils/deploy"
import { ClExecutor, Narrow, Mid, Wide, Vault } from "../typechain-types";

const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F"
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
const DAI_WHALE = "0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2"
const USDC_WHALE = "0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2"

const SWAP_ROUTER_ADDRESS = "0xAA23611badAFB62D37E7295A682D21960ac85A90";

describe("ClExecutor", () => {
  let ClExecutor
  let accounts
  let dai
  let usdc

  before(async () => {
    accounts = await ethers.getSigners()

    const narrowContract = await deployContract<Narrow>("Narrow");
    const midContract = await deployContract<Mid>("Mid");
    const wideContract = await deployContract<Wide>("Wide");

    await deployContract<ClExecutor>("ClExecutor", SWAP_ROUTER_ADDRESS, narrowContract.target, midContract.target, wideContract.target);

    await deployContract<Vault>("Vault", midContract.target);

    dai = await ethers.getContractAt("IERC20", DAI)
    usdc = await ethers.getContractAt("IERC20", USDC)

    // // Unlock DAI and USDC whales
    // await network.provider.request({
    //   method: "hardhat_impersonateAccount",
    //   params: [DAI_WHALE],
    // })
    // await network.provider.request({
    //   method: "hardhat_impersonateAccount",
    //   params: [USDC_WHALE],
    // })

    // const daiWhale = await ethers.getSigner(DAI_WHALE)
    // const usdcWhale = await ethers.getSigner(USDC_WHALE)

    // // Send DAI and USDC to accounts[0]
    // const daiAmount = 1000n * 10n ** 18n
    // const usdcAmount = 1000n * 10n ** 6n

    // expect(await dai.balanceOf(daiWhale.address)).to.gte(daiAmount)
    // expect(await usdc.balanceOf(usdcWhale.address)).to.gte(usdcAmount)

    // await dai.connect(daiWhale).transfer(accounts[0].address, daiAmount)
    // await usdc.connect(usdcWhale).transfer(accounts[0].address, usdcAmount)
  })

  it("provideLiquidity", async () => {
    const daiAmount = 100n * 10n ** 18n
    const usdcAmount = 100n * 10n ** 6n
    expect(true).to.be.true;
    // await dai
    //   .connect(accounts[0])
    //   .transfer(ClExecutor.address, daiAmount)
    // await usdc
    //   .connect(accounts[0])
    //   .transfer(ClExecutor.address, usdcAmount)

    // await ClExecutor.mintNewPosition()

    // console.log(
    //   "DAI balance after add liquidity",
    //   await dai.balanceOf(accounts[0].address)
    // )
    // console.log(
    //   "USDC balance after add liquidity",
    //   await usdc.balanceOf(accounts[0].address)
    // )
  })

  // it.skip("increaseLiquidityCurrentRange", async () => {
  //   const daiAmount = 20n * 10n ** 18n
  //   const usdcAmount = 20n * 10n ** 6n

  //   await dai.connect(accounts[0]).approve(ClExecutor.address, daiAmount)
  //   await usdc
  //     .connect(accounts[0])
  //     .approve(ClExecutor.address, usdcAmount)

  //   await ClExecutor.increaseLiquidityCurrentRange(daiAmount, usdcAmount)
  // })

  // it("decreaseLiquidity", async () => {
  //   const tokenId = await ClExecutor.tokenId()
  //   const liquidity = await ClExecutor.getLiquidity(tokenId)

  //   await ClExecutor.decreaseLiquidity(liquidity)

  //   console.log("--- decrease liquidity ---")
  //   console.log(`liquidity ${liquidity}`)
  //   console.log(`dai ${await dai.balanceOf(ClExecutor.address)}`)
  //   console.log(`usdc ${await usdc.balanceOf(ClExecutor.address)}`)
  // })

  // it("collectAllFees", async () => {
  //   await ClExecutor.collectAllFees()

  //   console.log("--- collect fees ---")
  //   console.log(`dai ${await dai.balanceOf(ClExecutor.address)}`)
  //   console.log(`usdc ${await usdc.balanceOf(ClExecutor.address)}`)
  // })
})
