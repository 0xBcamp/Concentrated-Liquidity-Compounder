//SPDX-License-Identifier: MITISwapRouter

pragma solidity >=0.7.5;

import {console2} from "forge-std/Test.sol";
import "../lib/TransferHelper.sol";
import "./interfaces/IClExecutor.sol";

contract ClExecutor is IClExecutor {
    /* Temporary */
    address constant NFT_MANAGER_ADDRESS =
        0xAA277CB7914b7e5514946Da92cb9De332Ce610EF;

    ISwapRouter immutable swapRouter;
    IPositionToken immutable narrowToken;
    IPositionToken immutable midToken;
    IPositionToken immutable wideToken;
    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(NFT_MANAGER_ADDRESS);

    IRamsesV2Factory ramsesV2Factory =
        IRamsesV2Factory(0xAA2cd7477c451E703f3B9Ba5663334914763edF8);

    IRamsesV2GaugeFactory ramsesV2GaugeFactory =
        IRamsesV2GaugeFactory(0xAA2fBD0C9393964aF7c66C1513e44A8CAAae4FDA);

    mapping(address => uint256[]) msgSenderToTokenIds;
    mapping(address => uint256) positionTokenToTokenId;

    constructor(
        address routerAddress,
        address narrowAddress,
        address midAddress,
        address wideAddress
    ) {
        swapRouter = ISwapRouter(routerAddress);
        narrowToken = IPositionToken(narrowAddress);
        midToken = IPositionToken(midAddress);
        wideToken = IPositionToken(wideAddress);
    }

    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(
        address operator,
        address,
        uint _tokenId,
        bytes calldata
    ) external returns (bytes4) {
        //_createDeposit(operator, _tokenId);
        return this.onERC721Received.selector;
    }

    /** Public setters **/

    /** Function to get WETH from ETH
     * @param wethAddress - address of WETH contract (0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 for mainnet)
     */
    function getWethFromEth(
        address wethAddress
    ) external payable returns (uint256) {
        IWeth wEth = IWeth(wethAddress);
        wEth.deposit{value: msg.value}();
        //wEth.approve(msg.sender, wEth.balanceOf(address(this)));
        wEth.transfer(msg.sender, wEth.balanceOf(address(this)));
        return wEth.balanceOf(msg.sender);
    }

    /**
    @dev Add liquidity to ramses and stake
    */
    function provideLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint24 fee,
        ranges priceRange
    ) external returns (uint256, uint256) {
        uint256 tokenId = 0;
        uint256 amountOfPositionToken = 0;
        IPositionToken token = wideToken;
        require(priceRange < ranges.MAX, "Price range not allowed");

        if (ranges.NARROW == priceRange) {
            token = narrowToken;
        } else if (ranges.MID == priceRange) {
            token = midToken;
        }
        if (false == isPositionCreated(address(token))) {
            console2.log("Creating new position...");
            (tokenId, amountOfPositionToken) = _createNewPosition(
                tokenA,
                tokenB,
                amountA,
                amountB,
                fee,
                token
            );
        } else {
            console2.log("Increasing new position...");
            tokenId = positionTokenToTokenId[address(token)];
            amountOfPositionToken = _increasePosition(
                tokenA,
                tokenB,
                amountA,
                amountB,
                fee,
                tokenId,
                token
            );
        }

        return (tokenId, amountOfPositionToken);
    }

    /**
    @dev Unstake and remove liquidity from ramses
    */
    function removeLiquidity(uint256 tokenId) external {
        (
            ,
            ,
            address tokenA,
            address tokenB,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);

        IRamsesV2Pool currentPool = IRamsesV2Pool(
            ramsesV2Factory.getPool(tokenA, tokenB, fee)
        ); /* The fee shall be also adjusted */
        _collectRewards(tokenId, address(currentPool));
        currentPool.burn(tickLower, tickUpper, liquidity);
        nonfungiblePositionManager.burn(tokenId);
    }

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256) {
        uint256 amountOut = 0;
        TransferHelper.safeTransferFrom(
            tokenIn,
            msg.sender,
            address(this),
            amountIn
        );

        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                // pool fee 0.05%
                fee: 500,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                // NOTE: In production, this value can be used to set the limit
                // for the price the swap will push the pool to,
                // which can help protect against price impact
                sqrtPriceLimitX96: 0
            });
        amountOut = swapRouter.exactInputSingle(params);
        return amountOut;
    }

    /**
    @dev Collect gathered fees, collect gathered RAM token, provide collected fees into the pool, boost rewards with RAM token
    */
    function compoundPosition(
        uint256 tokenId
    )
        public
        returns (uint256 amount0, uint256 amount1, uint256[] memory farmAmounts)
    {
        address token0;
        address token1;
        console2.log("Token ID: ", tokenId);
        (token0, token1) = getTokensInPosition(tokenId);
        console2.log("Tokens are:");
        console2.log(token0, token1);
        address poolAddress = ramsesV2Factory.getPool(token0, token1, 500);
        console2.log(">>>>>>>>>>>>>>>>>> POOOL ADDRESS ", address(poolAddress));

        (amount0, amount1, farmAmounts) = _collectRewards(tokenId, poolAddress);

        uint256 balance1 = IERC20(0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418)
            .balanceOf(address(this));

        uint256 balance2 = IERC20(0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7)
            .balanceOf(address(this));
        console2.log(balance1, balance2);
        console2.log(farmAmounts[0]);
        console2.log(farmAmounts[1]);
        if (balance2 > 0 || balance1 > 0) {
            //provideLiquidity(); /* to be filled */
            _boostRewards(
                tokenId,
                IERC20(0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418).balanceOf(
                    address(this)
                ),
                poolAddress
            );
        }
    }

    /** Private setters **/
    function _createNewPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint24 fee,
        IPositionToken token
    ) private returns (uint256, uint256) {
        uint160 sqrtPriceX96;
        int24 tickLower = -807270;
        int24 tickUpper = 807270;
        uint256 tokenId = 0;
        uint256 amount0 = 0;
        uint256 amount1 = 0;
        uint256 amountOfLiquidity = 0;
        /* Logical blocks - limits stack usage */
        {
            IRamsesV2Pool currentPool = IRamsesV2Pool(
                ramsesV2Factory.getPool(tokenA, tokenB, fee)
            ); /* The fee shall be also adjusted */
            // console2.log(tokenA, tokenB);
            // console2.log(
            //     ">>>>>>>>>>>>>>>>>> POOOL ADDRESS",
            //     address(currentPool)
            // );
            (sqrtPriceX96, , , , , , ) = currentPool.slot0();
        }
        (tickLower, tickUpper) = getTicksFromPositionRange(
            sqrtPriceX96,
            token.rangePercentage()
        );
        TransferHelper.safeTransferFrom(
            tokenA,
            msg.sender,
            address(this),
            amountA
        );

        TransferHelper.safeTransferFrom(
            tokenB,
            msg.sender,
            address(this),
            amountB
        );
        // Approve the position manager
        TransferHelper.safeApprove(
            tokenA,
            address(nonfungiblePositionManager),
            amountA
        );
        TransferHelper.safeApprove(
            tokenB,
            address(nonfungiblePositionManager),
            amountB
        );
        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams(
                tokenA,
                tokenB,
                fee,
                tickLower,
                tickUpper,
                amountA,
                amountB,
                0,
                0,
                address(this),
                (block.timestamp)
            );
        /* Logical blocks - limits stack usage */
        {
            (
                tokenId,
                amountOfLiquidity,
                amount0,
                amount1
            ) = nonfungiblePositionManager.mint(
                params
            ); /* state updated after interaction */
            msgSenderToTokenIds[msg.sender].push(tokenId);
            positionTokenToTokenId[address(token)] = tokenId;
            token.mint(amountOfLiquidity);
            token.transfer(msg.sender, amountOfLiquidity);
            // console2.log("Amount0: %d", amount0);
            // console2.log("Amount1: %d", amount1);
            // console2.log("Token Id: %d", tokenId);
            // console2.log("Amount of liquidity: %d", amountOfLiquidity);
        }

        return (tokenId, amountOfLiquidity);
    }

    function _increasePosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint24 fee,
        uint256 tokenId,
        IPositionToken token
    ) private returns (uint256) {
        uint256 amount0 = 0;
        uint256 amount1 = 0;
        uint256 amountOfLiquidity = 0;
        /* Logical blocks - limits stack usage */
        TransferHelper.safeTransferFrom(
            tokenA,
            msg.sender,
            address(this),
            amountA
        );

        TransferHelper.safeTransferFrom(
            tokenB,
            msg.sender,
            address(this),
            amountB
        );
        // Approve the position manager
        TransferHelper.safeApprove(
            tokenA,
            address(nonfungiblePositionManager),
            amountA
        );
        TransferHelper.safeApprove(
            tokenB,
            address(nonfungiblePositionManager),
            amountB
        );
        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager.IncreaseLiquidityParams(
                tokenId,
                amountA,
                amountB,
                0,
                0,
                (block.timestamp)
            );
        console2.log("Increasing liquidity.... ");
        /* Logical blocks - limits stack usage */
        {
            (amountOfLiquidity, amount0, amount1) = nonfungiblePositionManager
                .increaseLiquidity(
                    params
                ); /* state updated after interaction */

            bool tokenAdded = false;
            for (
                uint8 idx = 0;
                idx < msgSenderToTokenIds[msg.sender].length;
                idx++
            ) {
                if (msgSenderToTokenIds[msg.sender][idx] == tokenId) {
                    tokenAdded = true;
                    break;
                }
            }
            if (false == tokenAdded) {
                msgSenderToTokenIds[msg.sender].push(tokenId);
            }

            token.mint(amountOfLiquidity);
            token.transfer(msg.sender, amountOfLiquidity);
            // console2.log("Amount0: %d", amount0);
            // console2.log("Amount1: %d", amount1);
            // console2.log("Token Id: %d", tokenId);
            // console2.log("Amount of liquidity: %d", amountOfLiquidity);
        }

        return (amountOfLiquidity);
    }

    /* Attach veToken into the pool and vote for the pool distribution */
    function _boostRewards(
        uint256 tokenId,
        uint256 ramAmount,
        address poolAddress
    ) private returns (uint256) {
        uint256 veRamTokenId;
        address[] memory poolAddresses = new address[](1);
        uint256[] memory proportions = new uint256[](1);
        IVotingEscrow votingEscrow = IVotingEscrow(
            0xAAA343032aA79eE9a6897Dab03bef967c3289a06
        );
        IVoter voter = IVoter(0xAAA2564DEb34763E3d05162ed3f5C2658691f499);
        IMinter minter = IMinter(0xAAAA0b6BaefaeC478eB2d1337435623500AD4594);

        IERC20(0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418).approve(
            address(votingEscrow),
            ramAmount
        );
        poolAddresses[0] = poolAddress;
        proportions[0] = 1000000; // 100%
        veRamTokenId = votingEscrow.create_lock_for(
            ramAmount,
            126144000,
            address(this)
        ); // 126144000 - 4 years

        minter.update_period();

        voter.vote(veRamTokenId, poolAddresses, proportions);

        nonfungiblePositionManager.switchAttachment(tokenId, veRamTokenId);

        return veRamTokenId;
    }

    function _collectRewards(
        uint256 tokenId,
        address poolAddress
    )
        private
        returns (uint256 amount0, uint256 amount1, uint256[] memory farmAmounts)
    {
        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        IGaugeV2 gauge;
        // address[] memory gauges = new address[](1);
        address[] memory rewardTokens;
        // uint256[][] memory tokenIds = new uint256[][](1);
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        console2.log(
            ">>>>>>>>>>>>>>>>>> Gauge ADDRESS -- ",
            ramsesV2GaugeFactory.getGauge(poolAddress)
        );

        gauge = IGaugeV2(ramsesV2GaugeFactory.getGauge(poolAddress));
        rewardTokens = gauge.getRewardTokens();
        for (uint256 idx = 0; idx < rewardTokens.length; idx++) {
            console2.log("Reward token ", rewardTokens[idx]);
        }
        gauge.getReward(tokenId, rewardTokens);
        farmAmounts = new uint256[](rewardTokens.length);
        for (uint8 idx = 0; idx < rewardTokens.length; idx++) {
            farmAmounts[idx] = IERC20(rewardTokens[idx]).balanceOf(
                address(this)
            );
        }
        (amount0, amount1) = nonfungiblePositionManager.collect(params);
        // voter.claimClGaugeRewards(
        //     [0x44C8877b663E16c83dfa763Ec1F0231bb3e569c4],
        //     [
        //         [
        //             0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418,
        //             0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7
        //         ]
        //     ],
        //     [tokenId]
        // );
    }

    /** Public getters **/
    function getRamsesPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) public view returns (IRamsesV2Pool) {
        IRamsesV2Pool currentPool = IRamsesV2Pool(
            ramsesV2Factory.getPool(tokenA, tokenB, fee)
        ); /* The fee shall be also adjusted */
        return currentPool;
    }

    /// @notice Get the info of the given position
    function getOwnerDeposit(
        address _owner,
        uint256 _idx
    ) external view returns (address, address, uint128) {
        uint256 tokenId = msgSenderToTokenIds[_owner][_idx];
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);
        return (token0, token1, liquidity);
    }

    function getOwnerTokenIds(
        address _owner
    ) external view returns (uint256[] memory) {
        return msgSenderToTokenIds[_owner];
    }

    function getOwnerPosition(
        address _owner,
        uint256 _idx
    )
        external
        view
        returns (
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        uint256[] memory tokenIds = msgSenderToTokenIds[_owner];
        uint256 tokenId = tokenIds[_idx];
        (
            ,
            ,
            ,
            ,
            fee,
            tickLower,
            tickUpper,
            ,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1
        ) = nonfungiblePositionManager.positions(tokenId);
    }

    function getTokensInPosition(
        uint256 _tokenId
    ) public view returns (address token0, address token1) {
        (, , token0, token1, , , , , , , , ) = nonfungiblePositionManager
            .positions(_tokenId);
    }

    function getTicksInPosition(
        uint256 _tokenId
    ) public view returns (int24 tickLower, int24 tickUpper) {
        (, , , , , tickLower, tickUpper, , , , , ) = nonfungiblePositionManager
            .positions(_tokenId);
    }

    function getLiquidityOfPosition(
        uint256 tokenId
    ) external view returns (uint256 liquidity) {
        (, , , , , , , liquidity, , , , ) = nonfungiblePositionManager
            .positions(tokenId);
    }

    function _position(
        int24 tickLower,
        int24 tickUpper,
        address tokenA,
        address tokenB,
        uint24 fee
    )
        public
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), tickLower, tickUpper)
        );
        IRamsesV2Pool pool = getRamsesPool(tokenA, tokenB, fee);
        (
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1,

        ) = pool.positions(positionKey);
    }

    /* To rework - must be the constant offset */
    function getTicksFromPositionRange(
        uint160 sqrtPriceX96,
        uint8 percentage
    ) public pure returns (int24, int24) {
        int24 maxTick = 807270;
        int24 tickLower = -maxTick;
        int24 tickUpper = maxTick;
        int24 tick = 0;
        tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96); // rounding down and making tick spacing equal to % 10
        //console2.log(">>>>>>>>> Tick:", tick);
        tickLower = (((tick - ((maxTick * int24(uint24(percentage))) / 100)) /
            10) * 10);
        tickUpper = (((tick + ((maxTick * int24(uint24(percentage))) / 100)) /
            10) * 10);
        // console2.log(">>>>>>>>> ticks:");
        // console2.log(tickLower);
        // console2.log(tickUpper);
        return (tickLower, tickUpper);
    }

    function calculateTriggerToCompound(
        address positionToken
    ) public view returns (uint256) {}

    function getGatheredFeesInUsd(
        address positionToken
    ) public view returns (uint256) {}

    function getGatheredRamInUsd(
        address positionToken
    ) public view returns (uint256) {}

    function getPositionInUsd(
        address positionToken
    ) public view returns (uint256) {}

    /** Private getters **/
    function getGatheredFees(
        address positionToken
    ) private view returns (uint256) {}

    function getGatheredRamAndXram(
        address positionToken
    ) private view returns (uint256) {}

    function isPositionCreated(
        address tokenAddress
    ) public view returns (bool) {
        return
            IPositionToken(tokenAddress).totalSupply() > 0 &&
            positionTokenToTokenId[tokenAddress] != 0;
    }
}
