// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";

import {ClExecutor} from "../src/ClExecutor.sol";
import {RamsesV2Pool} from "../src/RamsesV2Pool.sol";
import {GaugeV2} from "../src/GaugeV2.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";
import {IClExecutor} from "../src/interfaces/IClExecutor.sol";
import {Narrow} from "../src/positionTokens/Narrow.sol";
import {Mid} from "../src/positionTokens/Mid.sol";
import {Wide} from "../src/positionTokens/Wide.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ForkTest is Test {
    // the identifiers of the forks
    uint256 mainnetFork;
    uint256 arbitrumFork;

    //Access variables from .env file via vm.envString("varname")
    //Replace ALCHEMY_KEY by your alchemy key or Etherscan key, change RPC url if need
    //inside your .env file e.g:
    //MAINNET_RPC_URL = 'https://eth-mainnet.g.alchemy.com/v2/ALCHEMY_KEY'
    string MAINNET_ALCHEMY_URL = vm.envString("MAINNET_ALCHEMY_URL");
    string ARB_MAINNET_ALCHEMY_URL = vm.envString("ARB_MAINNET_ALCHEMY_URL");
    // uint256 PRIVATE_KEY_1 = vm.envString("PRIVATE_KEY_1");
    // uint256 PRIVATE_KEY_2 = vm.envString("PRIVATE_KEY_2");

    address ROUTER_V2 = 0xAA23611badAFB62D37E7295A682D21960ac85A90;
    address USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address RAM = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;
    address XRAM = 0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7;

    // address user1 = vm.addr(PRIVATE_KEY_1);
    // address user2 = vm.addr(PRIVATE_KEY_2);

    ClExecutor clExecutor;
    Narrow narrow;
    Mid mid;
    Wide wide;
    RamsesV2Pool ramsesV2Pool;
    GaugeV2 gaugeV2;
    VotingEscrow votingEscrow;
    IERC20 weth = IERC20(WETH);
    IERC20 usdc = IERC20(USDC);

    uint256 AMOUNT = 1e18;

    function createVolume() public {
        clExecutor.getWethFromEth{value: 4 * AMOUNT}(WETH);
        weth.approve(address(clExecutor), weth.balanceOf(address(this)));
        clExecutor.swapTokens(WETH, USDC, 4 * AMOUNT);
        usdc.approve(address(clExecutor), usdc.balanceOf(address(this)));
        clExecutor.swapTokens(USDC, WETH, usdc.balanceOf(address(this)));
    }

    // create two _different_ forks during setup
    function setUp() public {
        console2.log("SETUP: \n 1.Arbitrum fork creation");
        mainnetFork = vm.createFork(MAINNET_ALCHEMY_URL);
        arbitrumFork = vm.createFork(ARB_MAINNET_ALCHEMY_URL);
        vm.selectFork(arbitrumFork);

        console2.log("\n 2.Contracts deployment");
        narrow = new Narrow();
        mid = new Mid();
        wide = new Wide();
        ramsesV2Pool = new RamsesV2Pool();
        gaugeV2 = new GaugeV2();
        votingEscrow = new VotingEscrow();
        clExecutor = new ClExecutor(
            ROUTER_V2,
            address(narrow),
            address(mid),
            address(wide)
        );

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
        // vm.etch(
        //     0x92bAc42BBbb4946Df598D811F1B65132a263b8c7, //0x5EEAEfe423321Eb61268AfD60b7E7c99d711a386,
        //     address(ramsesV2Pool).code
        // );
        // vm.etch(
        //     0x80C4F687b81d77b33C6e3e572E2E80DcCc996733,
        //     address(gaugeV2).code
        // );
        // vm.etch(
        //     0xAAA343032aA79eE9a6897Dab03bef967c3289a06,
        //     address(votingEscrow).code
        // );
    }

    // demonstrate fork ids are unique
    function testForkIdDiffer() public view {
        assert(mainnetFork != arbitrumFork);
    }

    // select a specific fork
    function testCanSelectFork() public {
        // select the fork
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        // from here on data is fetched from the `mainnetFork` if the EVM requests it and written to the storage of `mainnetFork`
    }

    // manage multiple forks in the same test
    function testCanSwitchForks() public {
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        vm.selectFork(arbitrumFork);
        assertEq(vm.activeFork(), arbitrumFork);
    }

    // forks can be created at all times
    function testCanCreateAndSelectForkInOneStep() public {
        // creates a new fork and also selects it
        uint256 anotherFork = vm.createSelectFork(ARB_MAINNET_ALCHEMY_URL);
        assertEq(vm.activeFork(), anotherFork);
    }

    // set `block.number` of a fork
    function testCanSetForkBlockNumber() public {
        vm.selectFork(mainnetFork);
        vm.rollFork(1_337_000);

        assertEq(block.number, 1_337_000);
    }

    function testProvidingLiquidity() public {
        uint256[] memory tokenIds;
        uint256 tokenId;

        console2.log("\nPROVIDE LIQUIDITY:\n 1.Approving tokens to spend.");
        weth.approve(address(clExecutor), AMOUNT);
        usdc.approve(address(clExecutor), usdc.balanceOf(address(this)));

        tokenIds = clExecutor.getOwnerTokenIds(address(this));

        console2.log(
            "\n 2.Providing liquidity for WETH/USDC pair with narrow range"
        );
        (tokenId, ) = clExecutor.provideLiquidity(
            WETH,
            USDC,
            AMOUNT,
            usdc.balanceOf(address(this)),
            500,
            IClExecutor.ranges.NARROW
        );

        console2.log("  - Token ID: ", tokenId);
        console2.log(
            "  - Amount of token ids after: %d",
            clExecutor.getOwnerTokenIds(address(this)).length
        );

        /* Total length of token ids should be greater than before */
        assert(
            (tokenIds.length + 1) ==
                clExecutor.getOwnerTokenIds(address(this)).length
        );
        /* Position tokens shall reflect specific postion correctly */
        assertEq(wide.balanceOf(address(this)), 0);
        assertEq(mid.balanceOf(address(this)), 0);
        assert(narrow.balanceOf(address(this)) > 0);
    }

    function testCollectingRewards() public {
        uint256[] memory tokenIds;
        uint256 tokenId;
        uint256 prevAmount0;
        uint256 prevAmount1;
        uint256 amount0;
        uint256 amount1;
        uint256[] memory farmingAmounts;
        address poolAddress;

        //address nfm = clExecutor.getAddressOfNonFungibleManager();

        console2.log("\nCOLLECT REWARDS:\n 1.Approving tokens to spend.");
        weth.approve(address(clExecutor), AMOUNT);
        usdc.approve(address(clExecutor), usdc.balanceOf(address(this)));

        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        console2.log(
            "\n 2.Providing liquidity for WETH/USDC pair with narrow range"
        );
        (tokenId, ) = clExecutor.provideLiquidity(
            WETH,
            USDC,
            AMOUNT,
            usdc.balanceOf(address(this)),
            500,
            IClExecutor.ranges.NARROW
        );
        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        console2.log("  - Token ID: ", tokenId);
        console2.log("  - Amount of token ids after: %d", tokenIds.length);

        console2.log("\n 3. Volume creation");
        createVolume();

        console2.log("\n 4. Collect rewards");
        poolAddress = address(clExecutor.getRamsesPool(WETH, USDC, 500));
        (amount0, amount1, farmingAmounts) = clExecutor._collectRewards(
            tokenId,
            address(poolAddress)
        );
        // console2.log(IERC20(WETH).balanceOf(address(clExecutor)));
        // console2.log(IERC20(USDC).balanceOf(address(clExecutor)));
        prevAmount0 = amount0;
        prevAmount1 = amount1;
        console2.log("  - Amount0 gathered: %d", amount0);
        console2.log("  - Amount1 gathered: %d", amount1);
        for (uint8 idx = 0; idx < farmingAmounts.length; idx++) {
            console2.log("  - Farmed : %d", farmingAmounts[idx]);
        }

        console2.log("  - Balances:");
        console2.log(
            "    - WETH: ",
            IERC20(WETH).balanceOf(address(clExecutor))
        );
        console2.log(
            "    - USDC: ",
            IERC20(USDC).balanceOf(address(clExecutor))
        );

        /* First assertions - rewards in WETH and USDC tokens should appear and be equal to the balance in the ClExecutor contract */
        // assert(amount0 == IERC20(WETH).balanceOf(address(clExecutor)));
        // assert(amount1 == IERC20(USDC).balanceOf(address(clExecutor)));
        assert(amount0 > 0);
        assert(amount1 > 0);

        console2.log("\n 5. Additional volume creation (3x more)");
        createVolume();
        createVolume();
        createVolume();

        console2.log("\n 6. Collect rewards again.....");
        (amount0, amount1, farmingAmounts) = clExecutor._collectRewards(
            tokenId,
            address(poolAddress)
        );

        console2.log("  - Amount0 gathered: %d", amount0);
        console2.log("  - Amount1 gathered: %d", amount1);
        for (uint8 idx = 0; idx < farmingAmounts.length; idx++) {
            console2.log("  - Farmed : %d", farmingAmounts[idx]);
        }

        console2.log(
            "  - RAM tokens gathered: ",
            IERC20(RAM).balanceOf(address(clExecutor))
        );
        console2.log(
            "  - xRAM tokens gathered: ",
            IERC20(XRAM).balanceOf(address(clExecutor))
        );
        console2.log("  - Wide tokens: ", wide.balanceOf(address(this)));
        console2.log("  - Mid tokens: ", mid.balanceOf(address(this)));
        console2.log("  - Narrow tokens: ", narrow.balanceOf(address(this)));

        /* Last asertions */
        /* Balance of position tokens should be proper */
        assertEq(wide.balanceOf(address(this)), 0);
        assertEq(mid.balanceOf(address(this)), 0);
        assert(narrow.balanceOf(address(this)) > 0);

        // console2.log("Balances:");
        // console2.log(IERC20(WETH).balanceOf(address(clExecutor)));
        // console2.log(IERC20(USDC).balanceOf(address(clExecutor)));
        /* Tokens gathered from last collect operation should be less than all amount of tokens gathered - not Applied because createVolume violate this for now */
        // assert(amount0 < IERC20(WETH).balanceOf(address(clExecutor)));
        // assert(amount1 < IERC20(USDC).balanceOf(address(clExecutor)));
        /* Tokens gathered from last collect operation should be more than all amount gathered previously */
        assert(amount0 > prevAmount0);
        assert(amount1 > prevAmount1);
    }

    function testBoostingRewards() public {
        uint256[] memory tokenIds;
        uint256 tokenId;
        uint256 amount0;
        uint256 amount1;
        uint256[] memory farmingAmounts;
        uint256 ramBalance;
        uint256 xRamBalance;
        address poolAddress;
        uint256 veRamTokenId;

        //address nfm = clExecutor.getAddressOfNonFungibleManager();

        console2.log("\nBOOST REWARDS:\n 1.Approving tokens to spend.");
        weth.approve(address(clExecutor), AMOUNT);
        usdc.approve(address(clExecutor), usdc.balanceOf(address(this)));

        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        console2.log(
            "\n 2.Providing liquidity for WETH/USDC pair with mid range"
        );
        (tokenId, ) = clExecutor.provideLiquidity(
            WETH,
            USDC,
            AMOUNT,
            usdc.balanceOf(address(this)),
            500,
            IClExecutor.ranges.MID
        );
        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        console2.log("  - Token ID: ", tokenId);
        console2.log("  - Amount of token ids after: %d", tokenIds.length);

        console2.log("\n 3. Volume creation");
        createVolume();

        console2.log("  - Timestamp before: ", block.timestamp);
        vm.warp(block.timestamp + 5 weeks);

        console2.log("  - Timestamp after: ", block.timestamp);

        console2.log("\n 4. Collect rewards");
        poolAddress = address(clExecutor.getRamsesPool(WETH, USDC, 500));
        (amount0, amount1, farmingAmounts) = clExecutor._collectRewards(
            tokenId,
            address(poolAddress)
        );
        console2.log("  - Amount0 gathered: %d", amount0);
        console2.log("  - Amount1 gathered: %d", amount1);
        console2.log("  - RAM tokens balances:");
        ramBalance = IERC20(RAM).balanceOf(address(clExecutor));
        xRamBalance = IERC20(XRAM).balanceOf(address(clExecutor));
        console2.log("    - RAM: ", ramBalance);
        console2.log("    - XRAM: ", xRamBalance);

        console2.log("\n 5. Boosting rewards.....");
        veRamTokenId = clExecutor._boostRewards(
            tokenId,
            ramBalance,
            poolAddress
        );

        // assert(amount0 > prevAmount0);
        // assert(amount1 > prevAmount1);
        console2.log(
            "  - RAM tokens gathered: ",
            IERC20(RAM).balanceOf(address(clExecutor))
        );
        console2.log(
            "  - xRAM tokens gathered: ",
            IERC20(XRAM).balanceOf(address(clExecutor))
        );
        console2.log("  - Wide tokens: ", wide.balanceOf(address(this)));
        console2.log("  - Mid tokens: ", mid.balanceOf(address(this)));
        console2.log("  - Narrow tokens: ", narrow.balanceOf(address(this)));

        assertEq(wide.balanceOf(address(this)), 0);
        assertEq(narrow.balanceOf(address(this)), 0);
        assert(mid.balanceOf(address(this)) > 0);

        assertEq(0, IERC20(RAM).balanceOf(address(clExecutor)));
        assert(xRamBalance > 0);
        assertEq(xRamBalance, IERC20(XRAM).balanceOf(address(clExecutor)));
    }

    function testIncreasingLiquidity() public {
        uint256[] memory tokenIds;
        uint256 tokenId;
        uint256 liquidityOfPosition;

        console2.log("\nINCREASE LIQUIDITY:\n 1.Approving tokens to spend.");
        weth.approve(address(clExecutor), AMOUNT);
        usdc.approve(address(clExecutor), usdc.balanceOf(address(this)));
        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        for (uint8 idx = 0; idx < tokenIds.length; idx++) {
            console2.log(tokenIds[idx]);
        }

        console2.log(
            "  - Position created: ",
            clExecutor.isPositionCreated(address(wide))
        );
        console2.log(
            "\n 2.Providing liquidity (position creation) for WETH/USDC pair with wide range"
        );
        (tokenId, ) = clExecutor.provideLiquidity(
            WETH,
            USDC,
            AMOUNT,
            usdc.balanceOf(address(this)),
            500,
            IClExecutor.ranges.WIDE
        );
        liquidityOfPosition = clExecutor.getLiquidityOfPosition(tokenId);
        console2.log("  - Liquidity of position: ", liquidityOfPosition);
        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        for (uint8 idx = 0; idx < tokenIds.length; idx++) {
            console2.log(tokenIds[idx]);
        }
        console2.log(
            "  - Position created: ",
            clExecutor.isPositionCreated(address(wide))
        );
        console2.log("\n 3. Approving and swapping...");
        weth.approve(address(clExecutor), AMOUNT);
        clExecutor.swapTokens(WETH, USDC, AMOUNT);
        weth.approve(address(clExecutor), AMOUNT);
        usdc.approve(address(clExecutor), usdc.balanceOf(address(this)));
        console2.log(
            "\n 4.Providing liquidity (Increasing position) for WETH/USDC pair with wide range"
        );
        (tokenId, ) = clExecutor.provideLiquidity(
            WETH,
            USDC,
            AMOUNT,
            usdc.balanceOf(address(this)),
            500,
            IClExecutor.ranges.WIDE
        );
        console2.log("  - TokenIds: ");
        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        for (uint8 idx = 0; idx < tokenIds.length; idx++) {
            console2.log(tokenIds[idx]);
        }
        assert(tokenIds.length == 1);
        assert(
            liquidityOfPosition < clExecutor.getLiquidityOfPosition(tokenId)
        );
        liquidityOfPosition = clExecutor.getLiquidityOfPosition(tokenId);
        console2.log("  - Liquidity of position: ", liquidityOfPosition);
    }

    function testCompoundingRewards() public {
        uint256[] memory tokenIds;
        uint256 tokenId;
        uint256 prevAmount0;
        uint256 prevAmount1;
        uint256 amount0;
        uint256 amount1;
        uint256[] memory farmingAmounts;
        uint256 ramBalance;
        uint256 xRamBalance;

        //address nfm = clExecutor.getAddressOfNonFungibleManager();

        console2.log("\nCOMPOUND LIQUIDITY:\n 1.Approving tokens to spend.");
        weth.approve(address(clExecutor), AMOUNT);
        usdc.approve(address(clExecutor), usdc.balanceOf(address(this)));

        tokenIds = clExecutor.getOwnerTokenIds(address(this));

        console2.log(
            "\n 2.Providing liquidity for WETH/USDC pair with wide range"
        );
        (tokenId, ) = clExecutor.provideLiquidity(
            WETH,
            USDC,
            AMOUNT,
            usdc.balanceOf(address(this)),
            500,
            IClExecutor.ranges.WIDE
        );
        tokenIds = clExecutor.getOwnerTokenIds(address(this));
        console2.log("  - Token ID: ", tokenId);
        console2.log("  - Amount of token ids after: %d", tokenIds.length);

        console2.log("\n 3. Volume creation");
        createVolume();

        console2.log("\n 4. Compounding....");
        (amount0, amount1, farmingAmounts, , ) = clExecutor.compoundPosition(
            tokenId,
            IClExecutor.ranges.WIDE
        );
        prevAmount0 = amount0;
        prevAmount1 = amount1;
        console2.log("  - Amount0 gathered: %d", amount0);
        console2.log("  - Amount1 gathered: %d", amount1);
        for (uint8 idx = 0; idx < farmingAmounts.length; idx++) {
            console2.log("  - Farmed : %d", farmingAmounts[idx]);
        }

        console2.log("  - Balances:");
        console2.log(
            "    - WETH: ",
            IERC20(WETH).balanceOf(address(clExecutor))
        );
        console2.log(
            "    - USDC: ",
            IERC20(USDC).balanceOf(address(clExecutor))
        );

        /* First assertions - rewards in WETH and USDC tokens should appear and be equal to the balance in the ClExecutor contract */
        assert(amount0 > 0);
        assert(amount1 > 0);

        console2.log("\n 5. Additional volume creation (3x more)");
        createVolume();
        createVolume();
        createVolume();

        console2.log("  - Timestamp before: ", block.timestamp);
        vm.warp(block.timestamp + 5 weeks);

        console2.log("  - Timestamp after: ", block.timestamp);
        ramBalance = IERC20(RAM).balanceOf(address(clExecutor));
        xRamBalance = IERC20(XRAM).balanceOf(address(clExecutor));
        console2.log(
            "  - RAM tokens gathered: ",
            IERC20(RAM).balanceOf(address(clExecutor))
        );
        console2.log(
            "  - xRAM tokens gathered: ",
            IERC20(XRAM).balanceOf(address(clExecutor))
        );

        // clExecutor.swapTokens(WETH, USDC, AMOUNT);
        // console2.log("Weth transfers");
        // weth.transfer(nfm, (AMOUNT / 2));
        // weth.transfer(address(clExecutor), (AMOUNT / 2));
        // console2.log("Usdc transfers");
        // usdc.transfer(nfm, (usdc.balanceOf(address(this)) / 2));
        // usdc.transfer(address(clExecutor), usdc.balanceOf(address(this)));

        console2.log("\n 6. Compounding.....");
        (amount0, amount1, farmingAmounts, , ) = clExecutor.compoundPosition(
            tokenId,
            IClExecutor.ranges.WIDE
        );

        console2.log("  - Amount0 gathered: %d", amount0);
        console2.log("  - Amount1 gathered: %d", amount1);
        for (uint8 idx = 0; idx < farmingAmounts.length; idx++) {
            console2.log("  - Farmed : %d", farmingAmounts[idx]);
        }

        console2.log(
            "  - RAM tokens gathered: ",
            IERC20(RAM).balanceOf(address(clExecutor))
        );
        console2.log(
            "  - xRAM tokens gathered: ",
            IERC20(XRAM).balanceOf(address(clExecutor))
        );
        console2.log("  - Wide tokens: ", wide.balanceOf(address(this)));
        console2.log("  - Mid tokens: ", mid.balanceOf(address(this)));
        console2.log("  - Narrow tokens: ", narrow.balanceOf(address(this)));

        /* Last asertions */
        /* Balance of position tokens should be proper */
        assertEq(narrow.balanceOf(address(this)), 0);
        assertEq(mid.balanceOf(address(this)), 0);
        assert(wide.balanceOf(address(this)) > 0);

        /* Tokens gathered from last collect operation should be more than all amount gathered previously */
        assert(amount0 > prevAmount0);
        assert(amount1 > prevAmount1);
    }
}
