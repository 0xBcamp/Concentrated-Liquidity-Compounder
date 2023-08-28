//SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "../interfaces/IRamsesV2Pool.sol";
import "../interfaces/ISwapRouter.sol";
import "../interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

enum ranges {
    NARROW,
    MID,
    WIDE_RANGE,
    MAX
}

contract CL_Compounder is ERC1155 {
    /* Temporary */
    address constant NFT_MANAGER_ADDRESS =
        0xAA277CB7914b7e5514946Da92cb9De332Ce610EF;

    ISwapRouter immutable swapRouter;
    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(NFT_MANAGER_ADDRESS);

    mapping(address => uint256[]) userToNftIds;

    constructor(address routerAddress) ERC1155("") {
        swapRouter = ISwapRouter(routerAddress);
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
        uint256 fee,
        ranges priceRange
    ) public returns (uint256) {
        uint160 sqrtPriceX96;
        IRamsesV2Pool currentPool = swapRouter.getPool(
            tokenA,
            tokenB,
            fee
        ); /* The fee shall be also adjusted */
        int24 tickLower = 0;
        int24 tickUpper = 0;

        require(priceRange < MAX, "Price range not allowed");

        (sqrtPriceX96, , , , , , ) = currentPool.slot0();

        if (ranges.NARROW == priceRange) {
            /* Range between +/- 2% range */
            tickLower = sqrtPriceX96 - ((sqrtPriceX96 * 2) / 100);
            tickUpper = sqrtPriceX96 + ((sqrtPriceX96 * 2) / 100);
            _mint(msg.sender, NARROW, amountA /* to be determmined */, "");
        } else if (ranges.MID == priceRange) {
            /* Range between +/- 5% range */
            tickLower = sqrtPriceX96 - ((sqrtPriceX96 * 5) / 100);
            tickUpper = sqrtPriceX96 + ((sqrtPriceX96 * 5) / 100);
            _mint(msg.sender, MID, amountA /* to be determmined */, "");
        } else {
            /* WIDE */
            /* Range between +/- 10% range */
            tickLower = sqrtPriceX96 - ((sqrtPriceX96 * 10) / 100);
            tickUpper = sqrtPriceX96 + ((sqrtPriceX96 * 10) / 100);
            _mint(msg.sender, WIDE, amountA /* to be determmined */, "");
        }

        MintParams params = MintParams(
            tokenA,
            tokenB,
            fee,
            amountA,
            amountB,
            tickLower,
            tickUpper
        );
        userToNftIds[msg.sender][priceRange] = nonfungiblePositionManager.mint(
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
        uint256 amountMin
    ) public returns (uint256) {
        bytes path = abi.encode(tokenIn, tokenOut);
        ExactOutputParams params = ExactOutputParams(
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
        provideLiquidity(); /* to be filled */
        _boostRewards(priceRange);
    }

    /** Private setters **/
    function _boostRewards(ranges priceRange) private returns (uint256) {}

    function _collectRewards(ranges priceRange) private returns (uint256) {
        bytes params = CollectParams(
            userToNftIds[msg.sender][priceRange],
            address(this),
            0 /* ?? */,
            0 /* ?? */
        );
        nonfungiblePositionManager.collect(params);
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        userToNftIds[to] = userToNftIds[from];
        userToNftIds[from] = 0;
        _safeTransferFrom(from, to, id, amount, data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public virtual override {
        require(
            from == _msgSender() || isApprovedForAll(from, _msgSender()),
            "ERC1155: caller is not token owner or approved"
        );
        require(ids < ranges.MAX);
        for (uint8 idx; idx < ids.length; idx) {
            userToNftIds[to][idx] = userToNftIds[from][idx];
            userToNftIds[from][idx] = 0;
        }

        _safeBatchTransferFrom(from, to, ids, amounts, data);
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
