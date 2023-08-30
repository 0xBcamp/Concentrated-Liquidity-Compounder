//SPDX-License-Identifier: MITISwapRouter

pragma solidity >=0.7.5;

import "./interfaces/ICLExecutor.sol";

contract ClExecutor is ICLExecutor {
    /* Temporary */
    address constant NFT_MANAGER_ADDRESS =
        0xAA277CB7914b7e5514946Da92cb9De332Ce610EF;

    ISwapRouter immutable swapRouter;
    IERC20MintableBurnable immutable narrowToken;
    IERC20MintableBurnable immutable midToken;
    IERC20MintableBurnable immutable wideToken;
    // INonfungiblePositionManager nonfungiblePositionManager =
    //     INonfungiblePositionManager(NFT_MANAGER_ADDRESS);

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
        int24 tickLower = 0;
        int24 tickUpper = 0;
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

        // MintParams params = MintParams(
        //     tokenA,
        //     tokenB,
        //     fee,
        //     amountA,
        //     amountB,
        //     tickLower,
        //     tickUpper
        // );
        // userToNftIds[msg.sender][priceRange] = nonfungiblePositionManager.mint(
        //     params
        // ); /* state updated after interaction */
    }

    /**
    @dev Unstake and remove liquidity from ramses
    */
    function removeLiquidity(address positionToken) public returns (uint256) {}

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountMin
    ) public returns (uint256) {
        bytes memory path = abi.encode(tokenIn, tokenOut);
        ISwapRouter.ExactOutputParams memory params = ISwapRouter
            .ExactOutputParams(
                path,
                msg.sender,
                (block.timestamp + 10),
                amountMin,
                IERC20(tokenIn).balanceOf(msg.sender) // amountInMax
            );
        swapRouter.exactOutput(params);
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

    function _collectRewards(ranges priceRange) private returns (uint256) {
        // bytes params = CollectParams(
        //     userToNftIds[msg.sender][priceRange],
        //     address(this),
        //     0 /* ?? */,
        //     0 /* ?? */
        // );
        // nonfungiblePositionManager.collect(params);
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
