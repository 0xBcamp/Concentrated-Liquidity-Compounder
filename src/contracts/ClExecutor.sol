//SPDX-License-Identifier: MITISwapRouter

pragma solidity >=0.7.5;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./interfaces/ICLExecutor.sol";
import "hardhat/console.sol";

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

    mapping(uint256 => Deposit) deposits;

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
    ) external returns (uint256) {
        uint256 tokenId = 0;
        uint8 percentage = 0;
        IERC20MintableBurnable token = wideToken;
        require(priceRange < ranges.MAX, "Price range not allowed");

        if (ranges.NARROW == priceRange) {
            /* Range between +/- 2% range */
            percentage = 2;
            token = narrowToken;
        } else if (ranges.MID == priceRange) {
            /* Range between +/- 5% range */
            percentage = 5;
            token = midToken;
        } else {
            /* WIDE */
            /* Range between +/- 10% range */
            percentage = 10;
        }
        tokenId = _createDepositReflection(
            tokenA,
            tokenB,
            amountA,
            amountB,
            fee,
            percentage,
            token
        );
        return tokenId;
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
        _collectRewards(tokenId);
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
    function compoundPosition(uint256 tokenId) public returns (uint256) {
        _collectRewards(tokenId);
        //provideLiquidity(); /* to be filled */
        _boostRewards(tokenId);
    }

    /** Private setters **/
    function _createDeposit(address owner, uint _tokenId) internal {
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

        ) = nonfungiblePositionManager.positions(_tokenId);
        // set the owner and data for position
        // operator is msg.sender
        deposits[_tokenId] = Deposit({
            owner: owner,
            liquidity: liquidity,
            token0: token0,
            token1: token1
        });

        console.log("Token id", _tokenId);
        console.log("Liquidity", liquidity);
    }

    function _createDepositReflection(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint24 fee,
        uint8 percentage,
        IERC20MintableBurnable token
    ) private returns (uint256) {
        uint160 sqrtPriceX96;
        int24 tickLower = TickMath.MIN_TICK;
        int24 tickUpper = TickMath.MAX_TICK;
        uint256 tokenId = 0;
        /* Logical blocks - limits stack usage */
        {
            IRamsesV2Pool currentPool = IRamsesV2Pool(
                ramsesV2Factory.getPool(tokenA, tokenB, fee)
            ); /* The fee shall be also adjusted */
            (sqrtPriceX96, , , , , , ) = currentPool.slot0();
            console.log("Price: %d", sqrtPriceX96);
        }
        /* Logical blocks - limits stack usage */
        {
            int24 tick = 0;
            tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

            tickLower = tick - ((tick * int24(uint24(percentage))) / 100);
            tickUpper = tick + ((tick * int24(uint24(percentage))) / 100);
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

        /* Logical blocks - limits stack usage */
        {
            uint256 amountOfLiquidity = 0;
            (
                tokenId,
                amountOfLiquidity,
                /* amount0 */
                /* amount1 */
                ,

            ) = nonfungiblePositionManager.mint(
                    params
                ); /* state updated after interaction */
            _createDeposit(msg.sender, tokenId);
            token.mint(amountOfLiquidity);
            token.transfer(msg.sender, amountOfLiquidity);
        }

        return tokenId;
    }

    function _boostRewards(uint256 tokenId) private returns (uint256) {}

    function _collectRewards(
        uint256 tokenId
    ) private returns (uint256 amount0, uint256 amount1) {
        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
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
