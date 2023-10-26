// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {ClExecutor} from "../src/ClExecutor.sol";
import {RamsesV2Pool} from "../src/RamsesV2Pool.sol";
import {GaugeV2} from "../src/GaugeV2.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";
import {IClExecutor} from "../src/interfaces/IClExecutor.sol";
import {Narrow} from "../src/positionTokens/Narrow.sol";
import {Mid} from "../src/positionTokens/Mid.sol";
import {Wide} from "../src/positionTokens/Wide.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


contract MyScript is Script {

    ClExecutor clExecutor;
    Narrow narrow;
    Mid mid;
    Wide wide;
    RamsesV2Pool ramsesV2Pool;
    GaugeV2 gaugeV2;
    VotingEscrow votingEscrow;
    IERC20 weth = IERC20(WETH);
    IERC20 usdc = IERC20(USDC);    

    address ROUTER_V2 = 0xAA23611badAFB62D37E7295A682D21960ac85A90;
    address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address RAM = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;
    address XRAM = 0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7;

    address custom_weth = 0x95bD8D42f30351685e96C62EDdc0d0613bf9a87A;

    uint256 AMOUNT = 1e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        narrow = new Narrow();
        mid = new Mid();
        wide = new Wide();

        clExecutor = new ClExecutor(ROUTER_V2,address(narrow), address(mid),address(wide));


        console2.log("  - Address of tester", address(this));
        console2.log("  - Address of clExecutor", address(clExecutor));

        console2.log("\n3. Configuration of position tokens:");
        narrow.setExecutor(address(clExecutor));
        mid.setExecutor(address(clExecutor));
        wide.setExecutor(address(clExecutor));

        console2.log("\n4. Getting wrapped ethereum");
        clExecutor.getWethFromEth{value: 4 * AMOUNT}(WETH);
        weth.approve(address(clExecutor), weth.balanceOf(address(this)));
        console2.log("Swapping WETH to USDC");
        clExecutor.swapTokens(WETH, USDC, AMOUNT);
        console2.log("success!");
        vm.stopBroadcast();
    }
}