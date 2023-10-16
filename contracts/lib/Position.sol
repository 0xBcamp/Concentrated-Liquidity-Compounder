// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma abicoder v2;

import {console2} from "forge-std/Test.sol";
import "./FullMath.sol";
import "./FixedPoint128.sol";
import "./FixedPoint32.sol";
import "./LiquidityMath.sol";
import "./SqrtPriceMath.sol";
import "./States.sol";
import "./Tick.sol";
import "./TickMath.sol";
import "./TickBitmap.sol";
import "./Oracle.sol";
import "./LiquidityAmounts.sol";

import "../interfaces/IVotingEscrow.sol";
import "../interfaces/IVoter.sol";

/// @title Position
/// @notice Positions represent an owner address' liquidity between a lower and upper tick boundary
/// @dev Positions store additional state for tracking fees owed to the position
library Position {
    // no limit if a your veRam reaches a threshold
    // if veRamRatio is more than 5% of total (5% * 1.5e18 =  7.5e16)
    uint256 internal constant veRamUncapThreshold = 7.5e16;

    /// @notice Returns the hash used to store positions in a mapping
    /// @param owner The address of the position owner
    /// @param index The index of the position
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return _hash The hash used to store positions in a mapping
    function positionHash(
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, index, tickLower, tickUpper));
    }

    /// @notice Returns the Info struct of a position, given an owner and position boundaries
    /// @param self The mapping containing all user positions
    /// @param owner The address of the position owner
    /// @param index The index of the position
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return position The position info struct of the given owners' position
    function get(
        mapping(bytes32 => PositionInfo) storage self,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (PositionInfo storage position) {
        position = self[positionHash(owner, index, tickLower, tickUpper)];
    }

    /// @notice Returns the BoostInfo struct of a position, given an owner, index, and position boundaries
    /// @param self The mapping containing all user boosted positions within the period
    /// @param owner The address of the position owner
    /// @param index The index of the position
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return position The position BoostInfo struct of the given owners' position within the period
    function get(
        PeriodBoostInfo storage self,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (BoostInfo storage position) {
        position = self.positions[
            positionHash(owner, index, tickLower, tickUpper)
        ];
    }

    /// @notice Credits accumulated fees to a user's position
    /// @param self The individual position to update
    /// @param liquidityDelta The change in pool liquidity as a result of the position update
    /// @param feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
    /// @param feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
    function _updatePositionLiquidity(
        PositionInfo storage self,
        States.PoolStates storage states,
        uint256 period,
        bytes32 _positionHash,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        PositionInfo memory _self = self;

        uint128 liquidityNext;
        if (liquidityDelta == 0) {
            require(_self.liquidity > 0, "NP"); // disallow pokes for 0 liquidity positions
            liquidityNext = _self.liquidity;
        } else {
            liquidityNext = LiquidityMath.addDelta(
                _self.liquidity,
                liquidityDelta
            );
        }

        // calculate accumulated fees
        uint128 tokensOwed0 = uint128(
            FullMath.mulDiv(
                feeGrowthInside0X128 - _self.feeGrowthInside0LastX128,
                _self.liquidity,
                FixedPoint128.Q128
            )
        );
        uint128 tokensOwed1 = uint128(
            FullMath.mulDiv(
                feeGrowthInside1X128 - _self.feeGrowthInside1LastX128,
                _self.liquidity,
                FixedPoint128.Q128
            )
        );

        // update the position
        if (liquidityDelta != 0) {
            self.liquidity = liquidityNext;
        }
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            // overflow is acceptable, have to withdraw before you hit type(uint128).max fees
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }

        // write checkpoint, push a checkpoint if the last period is different, overwrite if not
        uint256 checkpointLength = states
            .positionCheckpoints[_positionHash]
            .length;
        if (
            checkpointLength == 0 ||
            states
            .positionCheckpoints[_positionHash][checkpointLength - 1].period !=
            period
        ) {
            states.positionCheckpoints[_positionHash].push(
                PositionCheckpoint({period: period, liquidity: liquidityNext})
            );
        } else {
            states
            .positionCheckpoints[_positionHash][checkpointLength - 1]
                .liquidity = liquidityNext;
        }
    }

    /// @notice Updates boosted balances to a user's position
    /// @param self The individual boosted position to update
    /// @param boostedLiquidityDelta The change in pool liquidity as a result of the position update
    /// @param secondsPerBoostedLiquidityPeriodX128 The seconds in range gained per unit of liquidity, inside the position's tick boundaries for this period
    function _updateBoostedPosition(
        BoostInfo storage self,
        int128 liquidityDelta,
        int128 boostedLiquidityDelta,
        uint160 secondsPerLiquidityPeriodX128,
        uint160 secondsPerBoostedLiquidityPeriodX128
    ) internal {
        // negative expected sometimes, which is allowed
        int160 secondsPerLiquidityPeriodIntX128 = int160(
            secondsPerLiquidityPeriodX128
        );
        int160 secondsPerBoostedLiquidityPeriodIntX128 = int160(
            secondsPerBoostedLiquidityPeriodX128
        );

        self.boostAmount = LiquidityMath.addDelta(
            self.boostAmount,
            boostedLiquidityDelta
        );

        int160 secondsPerLiquidityPeriodStartX128 = self
            .secondsPerLiquidityPeriodStartX128;
        int160 secondsPerBoostedLiquidityPeriodStartX128 = self
            .secondsPerBoostedLiquidityPeriodStartX128;

        // take the difference to make the delta positive or zero
        secondsPerLiquidityPeriodIntX128 -= secondsPerLiquidityPeriodStartX128;
        secondsPerBoostedLiquidityPeriodIntX128 -= secondsPerBoostedLiquidityPeriodStartX128;

        // these int should never be negative
        if (secondsPerLiquidityPeriodIntX128 < 0) {
            secondsPerLiquidityPeriodIntX128 = 0;
        }
        if (secondsPerBoostedLiquidityPeriodIntX128 < 0) {
            secondsPerBoostedLiquidityPeriodIntX128 = 0;
        }

        int256 secondsDebtDeltaX96 = SafeCast.toInt256(
            FullMath.mulDivRoundingUp(
                liquidityDelta > 0
                    ? uint256(uint128(liquidityDelta))
                    : uint256(uint128(-liquidityDelta)),
                uint256(uint160(secondsPerLiquidityPeriodIntX128)),
                FixedPoint32.Q32
            )
        );

        int256 boostedSecondsDebtDeltaX96 = SafeCast.toInt256(
            FullMath.mulDivRoundingUp(
                boostedLiquidityDelta > 0
                    ? uint256(uint128(boostedLiquidityDelta))
                    : uint256(uint128(-boostedLiquidityDelta)),
                uint256(uint160(secondsPerBoostedLiquidityPeriodIntX128)),
                FixedPoint32.Q32
            )
        );

        self.boostedSecondsDebtX96 = boostedLiquidityDelta > 0
            ? self.boostedSecondsDebtX96 + boostedSecondsDebtDeltaX96
            : self.boostedSecondsDebtX96 - boostedSecondsDebtDeltaX96; // can't overflow since each period is way less than uint31

        self.secondsDebtX96 = liquidityDelta > 0
            ? self.secondsDebtX96 + secondsDebtDeltaX96
            : self.secondsDebtX96 - secondsDebtDeltaX96; // can't overflow since each period is way less than uint31
    }

    /// @notice Initializes secondsPerLiquidityPeriodStartX128 for a position
    /// @param self The individual boosted position to update
    /// @param position The individual position
    /// @param secondsInRangeParams Parameters used to find the seconds in range
    /// @param secondsPerLiquidityPeriodX128 The seconds in range gained per unit of liquidity, inside the position's tick boundaries for this period
    /// @param secondsPerBoostedLiquidityPeriodX128 The seconds in range gained per unit of liquidity, inside the position's tick boundaries for this period
    function initializeSecondsStart(
        BoostInfo storage self,
        PositionInfo storage position,
        PositionPeriodSecondsInRangeParams memory secondsInRangeParams,
        uint160 secondsPerLiquidityPeriodX128,
        uint160 secondsPerBoostedLiquidityPeriodX128
    ) internal {
        // record initialized
        self.initialized = true;

        // record owed tokens if liquidity > 0 (means position existed before period change)
        if (position.liquidity > 0) {
            (
                uint256 periodSecondsInsideX96,
                uint256 periodBoostedSecondsInsideX96
            ) = positionPeriodSecondsInRange(secondsInRangeParams);

            self.secondsDebtX96 = -int256(periodSecondsInsideX96);
            self.boostedSecondsDebtX96 = -int256(periodBoostedSecondsInsideX96);
        }

        // convert uint to int
        // negative expected sometimes, which is allowed
        int160 secondsPerLiquidityPeriodIntX128 = int160(
            secondsPerLiquidityPeriodX128
        );
        int160 secondsPerBoostedLiquidityPeriodIntX128 = int160(
            secondsPerBoostedLiquidityPeriodX128
        );

        self
            .secondsPerLiquidityPeriodStartX128 = secondsPerLiquidityPeriodIntX128;

        self
            .secondsPerBoostedLiquidityPeriodStartX128 = secondsPerBoostedLiquidityPeriodIntX128;
    }

    struct ModifyPositionParams {
        // the address that owns the position
        address owner;
        uint256 index;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        int128 liquidityDelta;
        uint256 veRamTokenId;
    }

    /// @dev Effect some changes to a position
    /// @param params the position details and the change to the position's liquidity to effect
    /// @return position a storage pointer referencing the position with the given owner and tick range
    /// @return amount0 the amount of token0 owed to the pool, negative if the pool should pay the recipient
    /// @return amount1 the amount of token1 owed to the pool, negative if the pool should pay the recipient
    function _modifyPosition(
        ModifyPositionParams memory params
    )
        external
        returns (PositionInfo storage position, int256 amount0, int256 amount1)
    {
        States.PoolStates storage states = States.getStorage();

        // check ticks
        require(params.tickLower < params.tickUpper, "TLU");
        require(params.tickLower >= TickMath.MIN_TICK, "TLM");
        require(params.tickUpper <= TickMath.MAX_TICK, "TUM");

        Slot0 memory _slot0 = states.slot0; // SLOAD for gas optimization

        int128 boostedLiquidityDelta;
        console2.log("Updating position...");
        (position, boostedLiquidityDelta) = _updatePosition(
            UpdatePositionParams({
                owner: params.owner,
                index: params.index,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta,
                tick: _slot0.tick,
                veRamTokenId: params.veRamTokenId
            })
        );
        if (params.liquidityDelta != 0 || boostedLiquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                // current tick is inside the passed range
                uint128 liquidityBefore = states.liquidity; // SLOAD for gas optimization
                uint128 boostedLiquidityBefore = states.boostedLiquidity;
                // write an oracle entry
                (
                    states.slot0.observationIndex,
                    states.slot0.observationCardinality
                ) = Oracle.write(
                    states.observations,
                    _slot0.observationIndex,
                    States._blockTimestamp(),
                    _slot0.tick,
                    liquidityBefore,
                    boostedLiquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );

                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );
                states.liquidity = LiquidityMath.addDelta(
                    liquidityBefore,
                    params.liquidityDelta
                );
                states.boostedLiquidity = LiquidityMath.addDelta(
                    boostedLiquidityBefore,
                    boostedLiquidityDelta
                );
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    struct UpdatePositionParams {
        // the owner of the position
        address owner;
        // the index of the position
        uint256 index;
        // the lower tick of the position's tick range
        int24 tickLower;
        // the upper tick of the position's tick range
        int24 tickUpper;
        // the amount liquidity changes by
        int128 liquidityDelta;
        // the current tick, passed to avoid sloads
        int24 tick;
        // the veRamTokenId to be attached
        uint256 veRamTokenId;
    }

    struct UpdatePositionCache {
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        bool flippedUpper;
        bool flippedLower;
        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
    }

    struct ObservationCache {
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        uint160 secondsPerBoostedLiquidityPeriodX128;
    }

    struct PoolBalanceCache {
        uint256 hypBalance0;
        uint256 hypBalance1;
        uint256 poolBalance0;
        uint256 poolBalance1;
    }

    struct BoostedLiquidityCache {
        uint256 veRamRatio;
        uint256 newBoostedLiquidity;
        uint160 lowerSqrtRatioX96;
        uint160 upperSqrtRatioX96;
        uint160 currentSqrtRatioX96;
    }

    struct VeRamBoostCache {
        uint256 veRamBoostUsedRatio;
        uint256 positionBoostUsedRatio;
    }

    /// @dev Gets and updates a position with the given liquidity delta
    /// @param params the position details and the change to the position's liquidity to effect
    function _updatePosition(
        UpdatePositionParams memory params
    )
        private
        returns (PositionInfo storage position, int128 boostedLiquidityDelta)
    {
        States.PoolStates storage states = States.getStorage();

        uint256 period = States._blockTimestamp() / 1 weeks;
        bytes32 _positionHash = positionHash(
            params.owner,
            params.index,
            params.tickLower,
            params.tickUpper
        );
        position = states.positions[_positionHash];
        BoostInfo storage boostedPosition = states.boostInfos[period].positions[
            _positionHash
        ];
        {
            // this is needed to determine attachment and newBoostedLiquidity
            uint128 newLiquidity = LiquidityMath.addDelta(
                position.liquidity,
                params.liquidityDelta
            );

            // detach if new liquidity is 0
            if (newLiquidity == 0) {
                _switchAttached(
                    position,
                    boostedPosition,
                    0,
                    period,
                    _positionHash
                );
                params.veRamTokenId = 0;
            }

            // type(uint256).max serves as a signal to not switch attachment
            if (params.veRamTokenId != type(uint256).max) {
                _switchAttached(
                    position,
                    boostedPosition,
                    params.veRamTokenId,
                    period,
                    _positionHash
                );
            }
            {
                BoostedLiquidityCache memory boostedLiquidityCache;
                (
                    boostedLiquidityCache.veRamRatio,
                    boostedLiquidityCache.newBoostedLiquidity
                ) = LiquidityMath.calculateBoostedLiquidity(
                    newLiquidity,
                    boostedPosition.veRamAmount,
                    states.boostInfos[period].totalVeRamAmount
                );
                if (boostedLiquidityCache.newBoostedLiquidity > 0) {
                    PoolBalanceCache memory poolBalanceCache;
                    poolBalanceCache.poolBalance0 = States.balance0();
                    poolBalanceCache.poolBalance1 = States.balance1();

                    boostedLiquidityCache.lowerSqrtRatioX96 = TickMath
                        .getSqrtRatioAtTick(params.tickLower);

                    boostedLiquidityCache.upperSqrtRatioX96 = TickMath
                        .getSqrtRatioAtTick(params.tickUpper);

                    boostedLiquidityCache.currentSqrtRatioX96 = states
                        .slot0
                        .sqrtPriceX96;

                    // boosted liquidity cap
                    // no limit if a your veRam reaches a threshold
                    if (
                        boostedLiquidityCache.veRamRatio < veRamUncapThreshold
                    ) {
                        uint160 midSqrtRatioX96 = TickMath.getSqrtRatioAtTick(
                            (params.tickLower + params.tickUpper) / 2
                        );

                        // check max balance allowed
                        {
                            uint256 maxBalance0 = LiquidityAmounts
                                .getAmount0ForLiquidity(
                                    midSqrtRatioX96,
                                    boostedLiquidityCache.upperSqrtRatioX96,
                                    type(uint128).max
                                );
                            uint256 maxBalance1 = LiquidityAmounts
                                .getAmount1ForLiquidity(
                                    boostedLiquidityCache.lowerSqrtRatioX96,
                                    midSqrtRatioX96,
                                    type(uint128).max
                                );

                            if (poolBalanceCache.poolBalance0 > maxBalance0) {
                                poolBalanceCache.hypBalance0 = maxBalance0;
                            } else {
                                poolBalanceCache.hypBalance0 = poolBalanceCache
                                    .poolBalance0;
                            }
                            if (poolBalanceCache.poolBalance1 > maxBalance1) {
                                poolBalanceCache.hypBalance1 = maxBalance1;
                            } else {
                                poolBalanceCache.hypBalance1 = poolBalanceCache
                                    .poolBalance1;
                            }
                        }
                        // hypothetical liquidity is found by using all of balance0 and balance1
                        // at this position's midpoint and range
                        // using midpoint to discourage making out of range positions
                        uint256 hypotheticalLiquidity = LiquidityAmounts
                            .getLiquidityForAmounts(
                                midSqrtRatioX96,
                                boostedLiquidityCache.lowerSqrtRatioX96,
                                boostedLiquidityCache.upperSqrtRatioX96,
                                poolBalanceCache.hypBalance0,
                                poolBalanceCache.hypBalance1
                            );

                        // limit newBoostedLiquidity to a portion of hypotheticalLiquidity based on how much veRam is attached
                        uint256 boostedLiquidityCap = FullMath.mulDiv(
                            hypotheticalLiquidity,
                            boostedLiquidityCache.veRamRatio,
                            1e18
                        );

                        if (
                            boostedLiquidityCache.newBoostedLiquidity >
                            boostedLiquidityCap
                        ) {
                            boostedLiquidityCache
                                .newBoostedLiquidity = boostedLiquidityCap;
                        }
                    }
                    console2.log("Ve Ram boost");
                    // veRam boost available
                    uint256 veRamBoostAvailable;
                    VeRamBoostCache memory veRamBoostCache;
                    {
                        // fetch existing data
                        veRamBoostCache.positionBoostUsedRatio = states
                            .boostInfos[period]
                            .veRamInfos[params.veRamTokenId]
                            .positionBoostUsedRatio[_positionHash];

                        veRamBoostCache.veRamBoostUsedRatio = states
                            .boostInfos[period]
                            .veRamInfos[params.veRamTokenId]
                            .veRamBoostUsedRatio;

                        // prevents underflows
                        veRamBoostCache.veRamBoostUsedRatio = veRamBoostCache
                            .veRamBoostUsedRatio >
                            veRamBoostCache.positionBoostUsedRatio
                            ? veRamBoostCache.veRamBoostUsedRatio -
                                veRamBoostCache.positionBoostUsedRatio
                            : 0;

                        uint256 veRamBoostAvailableRatio = 1e18 >
                            veRamBoostCache.veRamBoostUsedRatio
                            ? 1e18 - veRamBoostCache.veRamBoostUsedRatio
                            : 0;

                        // no limit if a your veRam reaches a threshold
                        // hypothetical balances still have to be calculated in case
                        // the veRam falls below threshold later
                        if (
                            boostedLiquidityCache.veRamRatio >=
                            veRamUncapThreshold
                        ) {
                            veRamBoostAvailableRatio = 1e18;
                        }
                        // assign hypBalances
                        {
                            uint256 maxBalance0 = 0;
                            uint256 maxBalance1 = 0;
                            console2.log("Geting amount ");
                            if (
                                boostedLiquidityCache.currentSqrtRatioX96 <
                                boostedLiquidityCache.lowerSqrtRatioX96
                            ) {
                                console2.log("IF Geting amount ");
                                maxBalance0 = LiquidityAmounts
                                    .getAmount0ForLiquidity(
                                        boostedLiquidityCache.lowerSqrtRatioX96,
                                        boostedLiquidityCache.upperSqrtRatioX96,
                                        type(uint128).max
                                    );
                            } else if (
                                boostedLiquidityCache.currentSqrtRatioX96 <
                                boostedLiquidityCache.upperSqrtRatioX96
                            ) {
                                console2.log("ELSE IF Geting amount ");
                                console2.log("0");
                                maxBalance0 = LiquidityAmounts
                                    .getAmount0ForLiquidity(
                                        boostedLiquidityCache
                                            .currentSqrtRatioX96,
                                        boostedLiquidityCache.upperSqrtRatioX96,
                                        type(uint128).max
                                    );
                                console2.log("1");
                                maxBalance1 = LiquidityAmounts
                                    .getAmount1ForLiquidity(
                                        boostedLiquidityCache.lowerSqrtRatioX96,
                                        boostedLiquidityCache
                                            .currentSqrtRatioX96,
                                        type(uint128).max
                                    );
                            } else {
                                console2.log("1");
                                maxBalance1 = LiquidityAmounts
                                    .getAmount1ForLiquidity(
                                        boostedLiquidityCache.lowerSqrtRatioX96,
                                        boostedLiquidityCache.upperSqrtRatioX96,
                                        type(uint128).max
                                    );
                            }

                            if (poolBalanceCache.poolBalance0 > maxBalance0) {
                                poolBalanceCache.hypBalance0 = maxBalance0;
                            } else {
                                poolBalanceCache.hypBalance0 = poolBalanceCache
                                    .poolBalance0;
                            }
                            if (poolBalanceCache.poolBalance1 > maxBalance1) {
                                poolBalanceCache.hypBalance1 = maxBalance1;
                            } else {
                                poolBalanceCache.hypBalance1 = poolBalanceCache
                                    .poolBalance1;
                            }
                        }
                        console2.log("Geting liquidity for amounts");
                        // hypothetical liquidity is found by using all of balance0 and balance1
                        // at current price to determine % boamountost used since boost will fill up fast otherwise
                        uint256 hypotheticalLiquidity = LiquidityAmounts
                            .getLiquidityForAmounts(
                                boostedLiquidityCache.currentSqrtRatioX96,
                                boostedLiquidityCache.lowerSqrtRatioX96,
                                boostedLiquidityCache.upperSqrtRatioX96,
                                poolBalanceCache.hypBalance0,
                                poolBalanceCache.hypBalance1
                            );
                        console2.log("Multiplications...");
                        hypotheticalLiquidity = FullMath.mulDiv(
                            hypotheticalLiquidity,
                            boostedLiquidityCache.veRamRatio,
                            1e18
                        );

                        veRamBoostAvailable = FullMath.mulDiv(
                            hypotheticalLiquidity,
                            veRamBoostAvailableRatio,
                            1e18
                        );

                        if (
                            boostedLiquidityCache.newBoostedLiquidity >
                            veRamBoostAvailable &&
                            boostedLiquidityCache.veRamRatio <
                            veRamUncapThreshold
                        ) {
                            boostedLiquidityCache
                                .newBoostedLiquidity = veRamBoostAvailable;
                        }

                        veRamBoostCache
                            .positionBoostUsedRatio = hypotheticalLiquidity == 0
                            ? 0
                            : FullMath.mulDiv(
                                boostedLiquidityCache.newBoostedLiquidity,
                                1e18,
                                hypotheticalLiquidity
                            );
                    }

                    // update veRamBoostUsedRatio and positionBoostUsedRatio
                    states
                        .boostInfos[period]
                        .veRamInfos[params.veRamTokenId]
                        .positionBoostUsedRatio[_positionHash] = veRamBoostCache
                        .positionBoostUsedRatio;

                    states
                        .boostInfos[period]
                        .veRamInfos[params.veRamTokenId]
                        .veRamBoostUsedRatio = uint128(
                        veRamBoostCache.veRamBoostUsedRatio +
                            veRamBoostCache.positionBoostUsedRatio
                    );
                }

                boostedLiquidityDelta = int128(
                    uint128(
                        boostedLiquidityCache.newBoostedLiquidity -
                            boostedPosition.boostAmount
                    )
                );
            }
        }

        UpdatePositionCache memory cache;

        cache.feeGrowthGlobal0X128 = states.feeGrowthGlobal0X128; // SLOAD for gas optimization
        cache.feeGrowthGlobal1X128 = states.feeGrowthGlobal1X128; // SLOAD for gas optimization
        // if we need to update the ticks, do it
        if (params.liquidityDelta != 0 || boostedLiquidityDelta != 0) {
            uint32 time = States._blockTimestamp();
            ObservationCache memory observationCache;
            (
                observationCache.tickCumulative,
                observationCache.secondsPerLiquidityCumulativeX128,
                observationCache.secondsPerBoostedLiquidityPeriodX128
            ) = Oracle.observeSingle(
                states.observations,
                time,
                0,
                states.slot0.tick,
                states.slot0.observationIndex,
                states.liquidity,
                states.boostedLiquidity,
                states.slot0.observationCardinality
            );
            cache.flippedLower = Tick.update(
                states._ticks,
                Tick.UpdateTickParams(
                    params.tickLower,
                    params.tick,
                    params.liquidityDelta,
                    boostedLiquidityDelta,
                    cache.feeGrowthGlobal0X128,
                    cache.feeGrowthGlobal1X128,
                    observationCache.secondsPerLiquidityCumulativeX128,
                    observationCache.secondsPerBoostedLiquidityPeriodX128,
                    observationCache.tickCumulative,
                    time,
                    false,
                    states.maxLiquidityPerTick
                )
            );
            console2.log("Ticks updates/fliping");
            cache.flippedUpper = Tick.update(
                states._ticks,
                Tick.UpdateTickParams(
                    params.tickUpper,
                    params.tick,
                    params.liquidityDelta,
                    boostedLiquidityDelta,
                    cache.feeGrowthGlobal0X128,
                    cache.feeGrowthGlobal1X128,
                    observationCache.secondsPerLiquidityCumulativeX128,
                    observationCache.secondsPerBoostedLiquidityPeriodX128,
                    observationCache.tickCumulative,
                    time,
                    true,
                    states.maxLiquidityPerTick
                )
            );

            if (cache.flippedLower) {
                TickBitmap.flipTick(
                    states.tickBitmap,
                    params.tickLower,
                    states.tickSpacing
                );
            }
            if (cache.flippedUpper) {
                TickBitmap.flipTick(
                    states.tickBitmap,
                    params.tickUpper,
                    states.tickSpacing
                );
            }
        }

        (cache.feeGrowthInside0X128, cache.feeGrowthInside1X128) = Tick
            .getFeeGrowthInside(
                states._ticks,
                params.tickLower,
                params.tickUpper,
                params.tick,
                cache.feeGrowthGlobal0X128,
                cache.feeGrowthGlobal1X128
            );

        {
            (
                uint160 secondsPerLiquidityPeriodX128,
                uint160 secondsPerBoostedLiquidityPeriodX128
            ) = Oracle.periodCumulativesInside(
                    uint32(period),
                    params.tickLower,
                    params.tickUpper
                );

            if (!boostedPosition.initialized) {
                initializeSecondsStart(
                    boostedPosition,
                    position,
                    PositionPeriodSecondsInRangeParams({
                        period: period,
                        owner: params.owner,
                        index: params.index,
                        tickLower: params.tickLower,
                        tickUpper: params.tickUpper
                    }),
                    secondsPerLiquidityPeriodX128,
                    secondsPerBoostedLiquidityPeriodX128
                );
            }
            console2.log("Update position Liquidity");
            _updatePositionLiquidity(
                position,
                states,
                period,
                _positionHash,
                params.liquidityDelta,
                cache.feeGrowthInside0X128,
                cache.feeGrowthInside1X128
            );
            _updateBoostedPosition(
                boostedPosition,
                params.liquidityDelta,
                boostedLiquidityDelta,
                secondsPerLiquidityPeriodX128,
                secondsPerBoostedLiquidityPeriodX128
            );
        }
        // clear any tick data that is no longer needed
        if (params.liquidityDelta < 0) {
            if (cache.flippedLower) {
                Tick.clear(states._ticks, params.tickLower);
            }
            if (cache.flippedUpper) {
                Tick.clear(states._ticks, params.tickUpper);
            }
        }
    }

    /// @notice updates attached veRam tokenId and veRam amount
    /// @dev can only be called in _updatePostion since boostedSecondsDebt needs to be updated when this is called
    /// @param position the user's position
    /// @param boostedPosition the user's boosted position
    /// @param veRamTokenId the veRam tokenId to switch to
    /// @param _positionHash the position's hash identifier
    function _switchAttached(
        PositionInfo storage position,
        BoostInfo storage boostedPosition,
        uint256 veRamTokenId,
        uint256 period,
        bytes32 _positionHash
    ) private {
        States.PoolStates storage states = States.getStorage();
        address _veRam = states.veRam;

        require(
            veRamTokenId == 0 ||
                msg.sender == states.nfpManager ||
                IVotingEscrow(_veRam).isApprovedOrOwner(
                    msg.sender,
                    veRamTokenId
                ),
            "TNA" // tokenId not authorized
        );

        int128 veRamAmountDelta;
        uint256 oldAttached = position.attachedVeRamId;

        // call detach and attach if needed
        if (veRamTokenId != oldAttached) {
            address _voter = states.voter;

            // detach, remove position from VeRamAttachments, and update total veRamAmount
            if (oldAttached != 0) {
                // call voter to notify detachment
                IVoter(_voter).detachTokenFromGauge(
                    oldAttached,
                    IVotingEscrow(_veRam).ownerOf(oldAttached)
                );

                // update times attached and veRamAmountDelta
                uint128 timesAttached = states
                    .boostInfos[period]
                    .veRamInfos[oldAttached]
                    .timesAttached;

                // only modify veRamAmountDelta if this is the last time
                // this veRam has been used to attach to a position
                if (timesAttached == 1) {
                    veRamAmountDelta -= boostedPosition.veRamAmount;
                }

                // update times this veRam NFT has been attached to this pool
                states
                    .boostInfos[period]
                    .veRamInfos[oldAttached]
                    .timesAttached = timesAttached - 1;

                // update veRamBoostUsedRatio and positionBoostUsedRatio
                uint256 positionBoostUsedRatio = states
                    .boostInfos[period]
                    .veRamInfos[oldAttached]
                    .positionBoostUsedRatio[_positionHash];

                states
                    .boostInfos[period]
                    .veRamInfos[oldAttached]
                    .veRamBoostUsedRatio -= uint128(positionBoostUsedRatio);

                states
                    .boostInfos[period]
                    .veRamInfos[oldAttached]
                    .positionBoostUsedRatio[_positionHash] = 0;
            }

            if (veRamTokenId != 0) {
                // call voter to notify attachment
                IVoter(_voter).attachTokenToGauge(
                    veRamTokenId,
                    IVotingEscrow(_veRam).ownerOf(veRamTokenId)
                );
            }

            position.attachedVeRamId = veRamTokenId;
        }

        if (veRamTokenId != 0) {
            // record new attachment amount
            int128 veRamAmountAfter = int128(
                uint128(IVotingEscrow(_veRam).balanceOfNFT(veRamTokenId))
            ); // can't overflow because bias is lower than locked, which is an int128
            boostedPosition.veRamAmount = veRamAmountAfter;

            // update times attached and veRamAmountDelta
            uint128 timesAttached = states
                .boostInfos[period]
                .veRamInfos[veRamTokenId]
                .timesAttached;

            // only add to veRam total amount if it's newly attached to the pool
            if (timesAttached == 0) {
                veRamAmountDelta += veRamAmountAfter;
            }

            // update times attached
            states.boostInfos[period].veRamInfos[veRamTokenId].timesAttached =
                timesAttached +
                1;
        } else {
            boostedPosition.veRamAmount = 0;
        }

        // update total veRam amount
        int128 totalVeRamAmount = states.boostInfos[period].totalVeRamAmount;
        totalVeRamAmount += veRamAmountDelta;
        if (totalVeRamAmount < 0) {
            totalVeRamAmount = 0;
        }

        states.boostInfos[period].totalVeRamAmount = totalVeRamAmount;
    }

    /// @notice gets the checkpoint directly before the period
    /// @dev returns the 0th index if there's no checkpoints
    /// @param checkpoints the position's checkpoints in storage
    /// @param period the period of interest
    function getCheckpoint(
        PositionCheckpoint[] storage checkpoints,
        uint256 period
    )
        internal
        view
        returns (uint256 checkpointIndex, uint256 checkpointPeriod)
    {
        {
            uint256 checkpointLength = checkpoints.length;

            // return 0 if length is 0
            if (checkpointLength == 0) {
                return (0, 0);
            }

            checkpointPeriod = checkpoints[0].period;

            // return 0 if first checkpoint happened after period
            if (checkpointPeriod > period) {
                return (0, 0);
            }

            checkpointIndex = checkpointLength - 1;
        }

        checkpointPeriod = checkpoints[checkpointIndex].period;

        // Find relevant checkpoint if latest checkpoint isn't before period of interest
        if (checkpointPeriod > period) {
            uint256 lower = 0;
            uint256 upper = checkpointIndex;

            while (upper > lower) {
                uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
                checkpointPeriod = checkpoints[center].period;
                if (checkpointPeriod == period) {
                    checkpointIndex = center;
                    return (checkpointIndex, checkpointPeriod);
                } else if (checkpointPeriod < period) {
                    lower = center;
                } else {
                    upper = center - 1;
                }
            }
            checkpointIndex = lower;
            checkpointPeriod = checkpoints[checkpointIndex].period;
        }

        return (checkpointIndex, checkpointPeriod);
    }

    struct PositionPeriodSecondsInRangeParams {
        uint256 period;
        address owner;
        uint256 index;
        int24 tickLower;
        int24 tickUpper;
    }

    // Get the period seconds in range of a specific position
    /// @return periodSecondsInsideX96 seconds the position was not in range for the period
    /// @return periodBoostedSecondsInsideX96 boosted seconds the period
    function positionPeriodSecondsInRange(
        PositionPeriodSecondsInRangeParams memory params
    )
        public
        view
        returns (
            uint256 periodSecondsInsideX96,
            uint256 periodBoostedSecondsInsideX96
        )
    {
        States.PoolStates storage states = States.getStorage();

        {
            uint256 currentPeriod = states.lastPeriod;
            require(params.period <= currentPeriod, "FTR"); // Future period, or current period hasn't been updated
        }

        bytes32 _positionHash = positionHash(
            params.owner,
            params.index,
            params.tickLower,
            params.tickUpper
        );

        uint256 liquidity;
        uint256 boostedLiquidity;
        int160 secondsPerLiquidityPeriodStartX128;
        int160 secondsPerBoostedLiquidityPeriodStartX128;

        {
            PositionCheckpoint[] storage checkpoints = states
                .positionCheckpoints[_positionHash];

            // get checkpoint at period, or last checkpoint before the period
            (uint256 checkpointIndex, uint256 checkpointPeriod) = getCheckpoint(
                checkpoints,
                params.period
            );

            // Return 0s if checkpointPeriod is 0
            if (checkpointPeriod == 0) {
                return (0, 0);
            }

            liquidity = checkpoints[checkpointIndex].liquidity;
            // use period instead of checkpoint period for boosted liquidity because it needs to be renewed weekly
            boostedLiquidity = states
                .boostInfos[params.period]
                .positions[_positionHash]
                .boostAmount;

            secondsPerLiquidityPeriodStartX128 = states
                .boostInfos[params.period]
                .positions[_positionHash]
                .secondsPerLiquidityPeriodStartX128;
            secondsPerBoostedLiquidityPeriodStartX128 = states
                .boostInfos[params.period]
                .positions[_positionHash]
                .secondsPerBoostedLiquidityPeriodStartX128;
        }

        (
            uint160 secondsPerLiquidityInsideX128,
            uint160 secondsPerBoostedLiquidityInsideX128
        ) = Oracle.periodCumulativesInside(
                uint32(params.period),
                params.tickLower,
                params.tickUpper
            );

        // underflow will be protected by sanity check
        secondsPerLiquidityInsideX128 = uint160(
            int160(secondsPerLiquidityInsideX128) -
                secondsPerLiquidityPeriodStartX128
        );

        secondsPerBoostedLiquidityInsideX128 = uint160(
            int160(secondsPerBoostedLiquidityInsideX128) -
                secondsPerBoostedLiquidityPeriodStartX128
        );

        BoostInfo storage boostPosition = states
            .boostInfos[params.period]
            .positions[_positionHash];

        int256 secondsDebtX96 = boostPosition.secondsDebtX96;
        int256 boostedSecondsDebtX96 = boostPosition.boostedSecondsDebtX96;

        // addDelta checks for under and overflows
        periodSecondsInsideX96 = FullMath.mulDiv(
            liquidity,
            secondsPerLiquidityInsideX128,
            FixedPoint32.Q32
        );

        // Need to check if secondsDebtX96>periodSecondsInsideX96, since rounding can cause underflows
        if (
            secondsDebtX96 < 0 ||
            periodSecondsInsideX96 > uint256(secondsDebtX96)
        ) {
            periodSecondsInsideX96 = LiquidityMath.addDelta256(
                periodSecondsInsideX96,
                -secondsDebtX96
            );
        } else {
            periodSecondsInsideX96 = 0;
        }

        // addDelta checks for under and overflows
        periodBoostedSecondsInsideX96 = FullMath.mulDiv(
            boostedLiquidity,
            secondsPerBoostedLiquidityInsideX128,
            FixedPoint32.Q32
        );

        // Need to check if secondsDebtX96>periodSecondsInsideX96, since rounding can cause underflows
        if (
            boostedSecondsDebtX96 < 0 ||
            periodBoostedSecondsInsideX96 > uint256(boostedSecondsDebtX96)
        ) {
            periodBoostedSecondsInsideX96 = LiquidityMath.addDelta256(
                periodBoostedSecondsInsideX96,
                -boostedSecondsDebtX96
            );
        } else {
            periodBoostedSecondsInsideX96 = 0;
        }

        // sanity
        if (periodSecondsInsideX96 > 1 weeks * FixedPoint96.Q96) {
            periodSecondsInsideX96 = 0;
        }

        if (periodBoostedSecondsInsideX96 > 1 weeks * FixedPoint96.Q96) {
            periodBoostedSecondsInsideX96 = 0;
        }
        // require(periodSecondsInsideX96 <= 1 weeks * FixedPoint96.Q96);
        // require(periodBoostedSecondsInsideX96 <= 1 weeks * FixedPoint96.Q96);
    }
}
