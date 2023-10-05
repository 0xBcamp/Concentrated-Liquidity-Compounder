import { expect } from "chai"
import { ethers, network } from "hardhat"
import { deployContract } from "../utils/deploy"
import { networkConfig } from "../helper-hardhat-config";
import { ClExecutor, Narrow, Mid, Wide, Vault } from "../typechain-types";

const DAI_WHALE = "0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2"
const USDC_WHALE = "0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2"

const SWAP_ROUTER_ADDRESS =
  describe("ClExecutor", () => {
    let clExecutorContract
    let accounts
    let dai
    let usdc
    let weth
    let mai
    let narrowContract
    let midContract
    let wideContract
    const chainId = network.config.chainId;

    before(async () => {
      accounts = await ethers.getSigners()

      narrowContract = await deployContract<Narrow>("Narrow");
      midContract = await deployContract<Mid>("Mid");
      wideContract = await deployContract<Wide>("Wide");

      clExecutorContract = await deployContract<ClExecutor>("ClExecutor", networkConfig[chainId]["RouterV2"], narrowContract.target, midContract.target, wideContract.target);
      narrowContract.setExecutor(clExecutorContract.target);
      midContract.setExecutor(clExecutorContract.target);
      wideContract.setExecutor(clExecutorContract.target);

      await deployContract<Vault>("Vault", midContract.target);

      dai = await ethers.getContractAt("IERC20", networkConfig[chainId]["dai"])
      usdc = await ethers.getContractAt("IERC20", networkConfig[chainId]["usdc"])
      weth = await ethers.getContractAt("IERC20", networkConfig[chainId]["weth"])
      mai = await ethers.getContractAt("IERC20", "0x3F56e0c36d275367b8C502090EDF38289b3dEa0d")

      await clExecutorContract.getWethFromEth(networkConfig[chainId]["weth"], { value: ethers.parseEther("90") });

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
      const usdcAmount = 1000n * 10n ** 6n
      await weth.approve(clExecutorContract.target, await weth.balanceOf(accounts[0]));
      // console.log("Pool: %s", await clExecutorContract.getRamsesPool(weth.target, usdc.target, 3000));
      // console.log("Pool: %s", await clExecutorContract.getRamsesPool(weth.target, usdc.target, 300));
      // console.log("Pool: %s", await clExecutorContract.getRamsesPool(weth.target, usdc.target, 500));
      // console.log("Pool: %s", await clExecutorContract.getRamsesPool(weth.target, usdc.target, 100));
      await clExecutorContract.swapTokens(weth.target, usdc.target, ethers.parseEther("10"));

      //await clExecutorContract.swapTokens(usdc.target, mai.target, usdcAmount);


      const wethBalance = await weth.balanceOf(accounts[0]);
      const usdcBalance = await usdc.balanceOf(accounts[0]);
      const maiBalance = await mai.balanceOf(accounts[0]);
      console.log("Balance of weth: %s", wethBalance);
      console.log("Balance of usdc: %s", usdcBalance);
      console.log("Balance of mai: %s", maiBalance);

      await weth.approve(clExecutorContract.target, wethBalance);
      await usdc.approve(clExecutorContract.target, usdcBalance);
      await mai.approve(clExecutorContract.target, maiBalance);
      let tx = await clExecutorContract.provideLiquidity(weth.target, usdc.target, ethers.parseEther("1"), usdcBalance, 500, 2);
      console.log(tx);
      //await clExecutorContract.provideLiquidity(mai.target, usdc.target, "3749172716860347732", "3386851", 500, 2);
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
