//SPDX-License-Identifier: MITISwapRouter

pragma solidity >=0.7.5;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./interfaces/ICLExecutor.sol";

contract ClExecutor is ICLExecutor {
    /* Temporary */
    address constant NFT_MANAGER_ADDRESS =
        0xAA277CB7914b7e5514946Da92cb9De332Ce610EF;

    ISwapRouter immutable swapRouter;
    IERC20MintableBurnable immutable narrowToken;
    IERC20MintableBurnable immutable midToken;
    IERC20MintableBurnable immutable wideToken;
    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(NFT_MANAGER_ADDRESS);

    IRamsesV2Factory ramsesV2Factory =
        IRamsesV2Factory(0xAA2cd7477c451E703f3B9Ba5663334914763edF8);

    mapping(address => uint256[]) userToNftIds;

    constructor(
        address routerAddress,
        address narrowAddress,
        address midAddress,
        address wideAddress
    ) {
        swapRouter = ISwapRouter(routerAddress);
        narrowToken = IERC20MintableBurnable(narrowAddress);
        midToken = IERC20MintableBurnable(midAddress);
        wideToken = IERC20MintableBurnable(wideAddress);
    }

    /** Public setters **/

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
    ) public returns (uint256) {
        uint160 sqrtPriceX96;
        IRamsesV2Pool currentPool = IRamsesV2Pool(
            ramsesV2Factory.getPool(tokenA, tokenB, fee)
        ); /* The fee shall be also adjusted */
        int24 tickLower = TickMath.MIN_TICK;
        int24 tickUpper = TickMath.MAX_TICK;
        uint256 amount = amountA; /* to be determmined */
        require(priceRange < ranges.MAX, "Price range not allowed");

        (sqrtPriceX96, , , , , , ) = currentPool.slot0();

        if (ranges.NARROW == priceRange) {
            /* Range between +/- 2% range */
            // tickLower = sqrtPriceX96 - ((sqrtPriceX96 * 2) / 100);
            // tickUpper = sqrtPriceX96 + ((sqrtPriceX96 * 2) / 100);
            narrowToken.mint(amount);
            narrowToken.transfer(msg.sender, amount);
        } else if (ranges.MID == priceRange) {
            /* Range between +/- 5% range */
            // tickLower = sqrtPriceX96 - ((sqrtPriceX96 * 5) / 100);
            // tickUpper = sqrtPriceX96 + ((sqrtPriceX96 * 5) / 100);
            midToken.mint(amount);
            midToken.transfer(msg.sender, amount);
        } else {
            /* WIDE */
            /* Range between +/- 10% range */
            // tickLower = sqrtPriceX96 - ((sqrtPriceX96 * 10) / 100);
            // tickUpper = sqrtPriceX96 + ((sqrtPriceX96 * 10) / 100);
            wideToken.mint(amount);
            wideToken.transfer(msg.sender, amount);
        }
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
                (block.timestamp + 10)
            );
        (
            userToNftIds[msg.sender][uint256(priceRange)],
            ,
            ,

        ) = nonfungiblePositionManager.mint(
            params
        ); /* state updated after interaction */
    }

    /**
    @dev Unstake and remove liquidity from ramses
    */
    function removeLiquidity(address positionToken) public returns (uint256) {}

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public returns (uint256) {
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
                // pool fee 0.3%
                fee: 3000,
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
    function compoundPosition(ranges priceRange) public returns (uint256) {
        _collectRewards(priceRange);
        //provideLiquidity(); /* to be filled */
        _boostRewards(priceRange);
    }

    /** Private setters **/
    function _boostRewards(ranges priceRange) private returns (uint256) {}

    function _collectRewards(
        ranges priceRange
    ) private returns (uint256 amount0, uint256 amount1) {
        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: userToNftIds[msg.sender][uint256(priceRange)],
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        // console.log("fee 0", amount0);
        // console.log("fee 1", amount1);
    }

    /** Public getters **/
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

    function getGatheredRam(
        address positionToken
    ) private view returns (uint256) {}
}
