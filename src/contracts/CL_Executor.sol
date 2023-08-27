//SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "../interfaces/IRamsesV2Pool.sol";
import "../interfaces/ISwapRouter.sol";

contract CL_Compounder {
    ISwapRouter immutable swapRouter;

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
        uint256 fee
    ) public returns (uint256) {
        IRamsesV2Pool currentPool = swapRouter.getPool(tokenA, tokenB, fee);
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
    ) public returns (uint256) {}

    /**
    @dev collect gathered fees, collect gathered RAM token, provide collected fees into the pool, boost rewards with RAM token
    */
    function compoundPosition(address positionToken) public returns (uint256) {}

    /** Private setters **/
    function _boostRewards(address positionToken) private returns (uint256) {}

    function _compoundFees(address positionToken) private returns (uint256) {}

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
