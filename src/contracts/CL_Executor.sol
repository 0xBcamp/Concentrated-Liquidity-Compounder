//SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "../interfaces/IRamsesV2Pool.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/INonfungiblePositionManager.sol";

contract CL_Compounder {
    /* Temporary */
    address constant NFT_MANAGER_ADDRESS =
        0xAA277CB7914b7e5514946Da92cb9De332Ce610EF;

    ISwapRouter immutable swapRouter;
    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(NFT_MANAGER_ADDRESS);

    mapping(address => uint256) positionTokenToNftId;

    constructor(address routerAddress) {
        swapRouter = ISwapRouter(routerAddress);
    }

    /** Public setters **/

    /**
    @dev add liquidity to ramses and stake
    */
    function provideLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 fee,
        int24 tickLower,
        int24 tickUpper
    ) public returns (uint256) {
        IRamsesV2Pool currentPool = swapRouter.getPool(tokenA, tokenB, fee);

        MintParams params = MintParams(
            tokenA,
            tokenB,
            fee,
            amountA,
            amountB,
            tickLower,
            tickUpper
        );
        nonfungiblePositionManager.mint(params);
        // swapRouter.mint(address(this), )
    }

    /**
    @dev unstake and remove liquidity from ramses
    */
    function removeLiquidity(address positionToken) public returns (uint256) {}

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountMin
    ) public returns (uint256) {
        bytes path = abi.encode(tokenIn, tokenOut);
        ExactOutputParams params = ExactOutputParams(
            path,
            msg.sender,
            (block.timestamp + 10),
            amountMin,
            IERC20(tokenIn).balanceOf(msg.sender)
        );
        swapRouter.exactOutput(params);
    }

    /**
    @dev collect gathered fees, collect gathered RAM token, provide collected fees into the pool, boost rewards with RAM token
    */
    function compoundPosition(address positionToken) public returns (uint256) {
        _collectRewards(positionToken);
        provideLiquidity();
        _boostRewards(positionToken);
    }

    /** Private setters **/
    function _boostRewards(address positionToken) private returns (uint256) {}

    function _collectRewards(address positionToken) private returns (uint256) {
        bytes params = CollectParams(
            positionTokenToNftId[positionToken],
            address(this),
            0 /* ?? */,
            0 /* ?? */
        );
        nonfungiblePositionManager.collect(params);
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
