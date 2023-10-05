// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./Tick.sol";
import "./States.sol";

/// @title Oracle
/// @notice Provides price and liquidity data useful for a wide variety of system designs
/// @dev Instances of stored oracle data, "observations", are collected in the oracle array
/// Every pool is initialized with an oracle array length of 1. Anyone can pay the SSTOREs to increase the
/// maximum length of the oracle array. New slots will be added when the array is fully populated.
/// Observations are overwritten when the full length of the oracle array is populated.
/// The most recent observation is available, independent of the length of the oracle array, by passing 0 to observe()
library Oracle {
    /// @notice Transforms a previous observation into a new observation, given the passage of time and the current tick and liquidity values
    /// @dev blockTimestamp _must_ be chronologically equal to or greater than last.blockTimestamp, safe for 0 or 1 overflows
    /// @param last The specified observation to be transformed
    /// @param blockTimestamp The timestamp of the new observation
    /// @param tick The active tick at the time of the new observation
    /// @param liquidity The total in-range liquidity at the time of the new observation
    /// @return Observation The newly populated observation
    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint128 boostedLiquidity
    ) internal pure returns (Observation memory) {
        uint32 delta = blockTimestamp - last.blockTimestamp;
        return
            Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: last.tickCumulative +
                    int56(tick) *
                    int32(delta),
                secondsPerLiquidityCumulativeX128: last
                    .secondsPerLiquidityCumulativeX128 +
                    ((uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)),
                secondsPerBoostedLiquidityPeriodX128: last
                    .secondsPerBoostedLiquidityPeriodX128 +
                    ((uint160(delta) << 128) /
                        (boostedLiquidity > 0 ? boostedLiquidity : 1)),
                initialized: true,
                boostedInRange: boostedLiquidity > 0
                    ? last.boostedInRange + delta
                    : last.boostedInRange
            });
    }

    /// @notice Initialize the oracle array by writing the first slot. Called once for the lifecycle of the observations array
    /// @param self The stored oracle array
    /// @param time The time of the oracle initialization, via block.timestamp truncated to uint32
    /// @return cardinality The number of populated elements in the oracle array
    /// @return cardinalityNext The new length of the oracle array, independent of population
    function initialize(
        Observation[65535] storage self,
        uint32 time
    ) external returns (uint16 cardinality, uint16 cardinalityNext) {
        self[0] = Observation({
            blockTimestamp: time,
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0,
            secondsPerBoostedLiquidityPeriodX128: 0,
            initialized: true,
            boostedInRange: 0
        });
        return (1, 1);
    }

    /// @notice Writes an oracle observation to the array
    /// @dev Writable at most once per block. Index represents the most recently written element. cardinality and index must be tracked publicly.
    /// If the index is at the end of the allowable array length (according to cardinality), and the next cardinality
    /// is greater than the current one, cardinality may be increased. This restriction is created to preserve ordering.
    /// @param self The stored oracle array
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param blockTimestamp The timestamp of the new observation
    /// @param tick The active tick at the time of the new observation
    /// @param liquidity The total in-range liquidity at the time of the new observation
    /// @param cardinality The number of populated elements in the oracle array
    /// @param cardinalityNext The new length of the oracle array, independent of population
    /// @return indexUpdated The new index of the most recently written element in the oracle array
    /// @return cardinalityUpdated The new cardinality of the oracle array
    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint128 boostedLiquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) external returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        Observation memory last = self[index];

        // early return if we've already written an observation this block
        if (last.blockTimestamp == blockTimestamp) return (index, cardinality);

        // if the conditions are right, we can bump the cardinality
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        indexUpdated = (index + 1) % cardinalityUpdated;
        self[indexUpdated] = transform(
            last,
            blockTimestamp,
            tick,
            liquidity,
            boostedLiquidity
        );
    }

    /// @notice Prepares the oracle array to store up to `next` observations
    /// @param self The stored oracle array
    /// @param current The current next cardinality of the oracle array
    /// @param next The proposed next cardinality which will be populated in the oracle array
    /// @return next The next cardinality which will be populated in the oracle array
    function grow(
        Observation[65535] storage self,
        uint16 current,
        uint16 next
    ) external returns (uint16) {
        require(current > 0, "I");
        // no-op if the passed next value isn't greater than the current next value
        if (next <= current) return current;
        // store in each slot to prevent fresh SSTOREs in swaps
        // this data will not be used because the initialized boolean is still false
        for (uint16 i = current; i < next; i++) self[i].blockTimestamp = 1;
        return next;
    }

    /// @notice comparator for 32-bit timestamps
    /// @dev safe for 0 or 1 overflows, a and b _must_ be chronologically before or equal to time
    /// @param time A timestamp truncated to 32 bits
    /// @param a A comparison timestamp from which to determine the relative position of `time`
    /// @param b From which to determine the relative position of `time`
    /// @return bool Whether `a` is chronologically <= `b`
    function lte(uint32 time, uint32 a, uint32 b) internal pure returns (bool) {
        // if there hasn't been overflow, no need to adjust
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2 ** 32;
        uint256 bAdjusted = b > time ? b : b + 2 ** 32;

        return aAdjusted <= bAdjusted;
    }

    /// @notice Fetches the observations beforeOrAt and atOrAfter a target, i.e. where [beforeOrAt, atOrAfter] is satisfied.
    /// The result may be the same observation, or adjacent observations.
    /// @dev The answer must be contained in the array, used when the target is located within the stored observation
    /// boundaries: older than the most recent observation and younger, or the same age as, the oldest observation
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param target The timestamp at which the reserved observation should be for
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param cardinality The number of populated elements in the oracle array
    /// @return beforeOrAt The observation recorded before, or at, the target
    /// @return atOrAfter The observation recorded at, or after, the target
    function binarySearch(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    )
        internal
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint256 l = (index + 1) % cardinality; // oldest observation
        uint256 r = l + cardinality - 1; // newest observation
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // we've landed on an uninitialized tick, keep searching higher (more recently)
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);

            // check if we've found the answer!
            if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp))
                break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    /// @notice Fetches the observations beforeOrAt and atOrAfter a given target, i.e. where [beforeOrAt, atOrAfter] is satisfied
    /// @dev Assumes there is at least 1 initialized observation.
    /// Used by observeSingle() to compute the counterfactual accumulator values as of a given block timestamp.
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param target The timestamp at which the reserved observation should be for
    /// @param tick The active tick at the time of the returned or simulated observation
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param liquidity The total pool liquidity at the time of the call
    /// @param cardinality The number of populated elements in the oracle array
    /// @return beforeOrAt The observation which occurred at, or before, the given timestamp
    /// @return atOrAfter The observation which occurred at, or after, the given timestamp
    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint128 boostedLiquidity,
        uint16 cardinality
    )
        internal
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        // optimistically set before to the newest observation
        beforeOrAt = self[index];

        // if the target is chronologically at or after the newest observation, we can early return
        if (lte(time, beforeOrAt.blockTimestamp, target)) {
            if (beforeOrAt.blockTimestamp == target) {
                // if newest observation equals target, we're in the same block, so we can ignore atOrAfter
                return (beforeOrAt, atOrAfter);
            } else {
                // otherwise, we need to transform
                return (
                    beforeOrAt,
                    transform(
                        beforeOrAt,
                        target,
                        tick,
                        liquidity,
                        boostedLiquidity
                    )
                );
            }
        }

        // now, set before to the oldest observation
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // ensure that the target is chronologically at or after the oldest observation
        require(lte(time, beforeOrAt.blockTimestamp, target), "OLD");

        // if we've reached this point, we have to binary search
        return binarySearch(self, time, target, index, cardinality);
    }

    /// @dev Reverts if an observation at or before the desired observation timestamp does not exist.
    /// 0 may be passed as `secondsAgo' to return the current cumulative values.
    /// If called with a timestamp falling between two observations, returns the counterfactual accumulator values
    /// at exactly the timestamp between the two observations.
    /// @param self The stored oracle array
    /// @param time The current block timestamp
    /// @param secondsAgo The amount of time to look back, in seconds, at which point to return an observation
    /// @param tick The current tick
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param liquidity The current in-range pool liquidity
    /// @param cardinality The number of populated elements in the oracle array
    /// @return tickCumulative The tick * time elapsed since the pool was first initialized, as of `secondsAgo`
    /// @return secondsPerLiquidityCumulativeX128 The time elapsed / max(1, liquidity) since the pool was first initialized, as of `secondsAgo`
    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint128 boostedLiquidity,
        uint16 cardinality
    )
        public
        view
        returns (
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            uint160 periodSecondsPerBoostedLiquidityX128
        )
    {
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.blockTimestamp != time) {
                last = transform(last, time, tick, liquidity, boostedLiquidity);
            }
            return (
                last.tickCumulative,
                last.secondsPerLiquidityCumulativeX128,
                last.secondsPerBoostedLiquidityPeriodX128
            );
        }

        uint32 target = time - secondsAgo;

        (
            Observation memory beforeOrAt,
            Observation memory atOrAfter
        ) = getSurroundingObservations(
                self,
                time,
                target,
                tick,
                index,
                liquidity,
                boostedLiquidity,
                cardinality
            );

        if (target == beforeOrAt.blockTimestamp) {
            // we're at the left boundary
            return (
                beforeOrAt.tickCumulative,
                beforeOrAt.secondsPerLiquidityCumulativeX128,
                beforeOrAt.secondsPerBoostedLiquidityPeriodX128
            );
        } else if (target == atOrAfter.blockTimestamp) {
            // we're at the right boundary
            return (
                atOrAfter.tickCumulative,
                atOrAfter.secondsPerLiquidityCumulativeX128,
                atOrAfter.secondsPerBoostedLiquidityPeriodX128
            );
        } else {
            // we're in the middle
            uint32 observationTimeDelta = atOrAfter.blockTimestamp -
                beforeOrAt.blockTimestamp;
            uint32 targetDelta = target - beforeOrAt.blockTimestamp;
            return (
                beforeOrAt.tickCumulative +
                    ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) /
                        int32(observationTimeDelta)) *
                    int32(targetDelta),
                beforeOrAt.secondsPerLiquidityCumulativeX128 +
                    uint160(
                        (uint256(
                            atOrAfter.secondsPerLiquidityCumulativeX128 -
                                beforeOrAt.secondsPerLiquidityCumulativeX128
                        ) * targetDelta) / observationTimeDelta
                    ),
                beforeOrAt.secondsPerBoostedLiquidityPeriodX128 +
                    uint160(
                        (uint256(
                            atOrAfter.secondsPerBoostedLiquidityPeriodX128 -
                                beforeOrAt.secondsPerBoostedLiquidityPeriodX128
                        ) * targetDelta) / observationTimeDelta
                    )
            );
        }
    }

    /// @notice Returns the accumulator values as of each time seconds ago from the given time in the array of `secondsAgos`
    /// @dev Reverts if `secondsAgos` > oldest observation
    /// @param self The stored oracle array
    /// @param time The current block.timestamp
    /// @param secondsAgos Each amount of time to look back, in seconds, at which point to return an observation
    /// @param tick The current tick
    /// @param index The index of the observation that was most recently written to the observations array
    /// @param liquidity The current in-range pool liquidity
    /// @param cardinality The number of populated elements in the oracle array
    /// @return tickCumulatives The tick * time elapsed since the pool was first initialized, as of each `secondsAgo`
    /// @return secondsPerLiquidityCumulativeX128s The cumulative seconds / max(1, liquidity) since the pool was first initialized, as of each `secondsAgo`
    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint128 boostedLiquidity,
        uint16 cardinality
    )
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s,
            uint160[] memory periodSecondsPerBoostedLiquidityX128s
        )
    {
        require(cardinality > 0, "I");

        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        periodSecondsPerBoostedLiquidityX128s = new uint160[](
            secondsAgos.length
        );

        for (uint256 i = 0; i < secondsAgos.length; i++) {
            (
                tickCumulatives[i],
                secondsPerLiquidityCumulativeX128s[i],
                periodSecondsPerBoostedLiquidityX128s[i]
            ) = observeSingle(
                self,
                time,
                secondsAgos[i],
                tick,
                index,
                liquidity,
                boostedLiquidity,
                cardinality
            );
        }
    }

    function newPeriod(
        Observation[65535] storage self,
        uint16 index,
        uint256 period
    )
        external
        returns (
            uint160 secondsPerLiquidityCumulativeX128,
            uint160 secondsPerBoostedLiquidityCumulativeX128,
            uint32 boostedInRange
        )
    {
        Observation memory last = self[index];
        States.PoolStates storage states = States.getStorage();

        uint32 delta = uint32(period) * 1 weeks - last.blockTimestamp;

        secondsPerLiquidityCumulativeX128 =
            last.secondsPerLiquidityCumulativeX128 +
            ((uint160(delta) << 128) /
                (states.liquidity > 0 ? states.liquidity : 1));

        secondsPerBoostedLiquidityCumulativeX128 =
            last.secondsPerBoostedLiquidityPeriodX128 +
            ((uint160(delta) << 128) /
                (states.boostedLiquidity > 0 ? states.boostedLiquidity : 1));

        boostedInRange = states.boostedLiquidity > 0
            ? last.boostedInRange + delta
            : last.boostedInRange;

        self[index] = Observation({
            blockTimestamp: uint32(period) * 1 weeks,
            tickCumulative: last.tickCumulative,
            secondsPerLiquidityCumulativeX128: secondsPerLiquidityCumulativeX128,
            secondsPerBoostedLiquidityPeriodX128: secondsPerBoostedLiquidityCumulativeX128,
            initialized: last.initialized,
            boostedInRange: 0
        });
    }

    struct SnapShot {
        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint160 secondsPerBoostedLiquidityOutsideLowerX128;
        uint160 secondsPerBoostedLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;
    }

    struct SnapshotCumulativesInsideCache {
        uint32 time;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        uint160 secondsPerBoostedLiquidityCumulativeX128;
    }

    /// @notice Returns a snapshot of the tick cumulative, seconds per liquidity and seconds inside a tick range
    /// @dev Snapshots must only be compared to other snapshots, taken over a period for which a position existed.
    /// I.e., snapshots cannot be compared if a position is not held for the entire period between when the first
    /// snapshot is taken and the second snapshot is taken. Boosted data is only valid if it's within the same period
    /// @param tickLower The lower tick of the range
    /// @param tickUpper The upper tick of the range
    /// @return tickCumulativeInside The snapshot of the tick accumulator for the range
    /// @return secondsPerLiquidityInsideX128 The snapshot of seconds per liquidity for the range
    /// @return secondsPerBoostedLiquidityInsideX128 The snapshot of seconds per boosted liquidity for the range
    /// @return secondsInside The snapshot of seconds per liquidity for the range
    function snapshotCumulativesInside(
        int24 tickLower,
        int24 tickUpper
    )
        external
        view
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint160 secondsPerBoostedLiquidityInsideX128,
            uint32 secondsInside
        )
    {
        States.PoolStates storage states = States.getStorage();

        TickInfo storage lower = states._ticks[tickLower];
        TickInfo storage upper = states._ticks[tickUpper];

        SnapShot memory snapshot;

        {
            uint256 period = States._blockTimestamp() / 1 weeks;
            bool initializedLower;
            (
                snapshot.tickCumulativeLower,
                snapshot.secondsPerLiquidityOutsideLowerX128,
                snapshot.secondsPerBoostedLiquidityOutsideLowerX128,
                snapshot.secondsOutsideLower,
                initializedLower
            ) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                uint160(
                    lower.periodSecondsPerBoostedLiquidityOutsideX128[period]
                ),
                lower.secondsOutside,
                lower.initialized
            );
            require(initializedLower);

            bool initializedUpper;
            (
                snapshot.tickCumulativeUpper,
                snapshot.secondsPerLiquidityOutsideUpperX128,
                snapshot.secondsPerBoostedLiquidityOutsideUpperX128,
                snapshot.secondsOutsideUpper,
                initializedUpper
            ) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                uint160(
                    upper.periodSecondsPerBoostedLiquidityOutsideX128[period]
                ),
                upper.secondsOutside,
                upper.initialized
            );
            require(initializedUpper);
        }

        Slot0 memory _slot0 = states.slot0;

        if (_slot0.tick < tickLower) {
            return (
                snapshot.tickCumulativeLower - snapshot.tickCumulativeUpper,
                snapshot.secondsPerLiquidityOutsideLowerX128 -
                    snapshot.secondsPerLiquidityOutsideUpperX128,
                snapshot.secondsPerBoostedLiquidityOutsideLowerX128 -
                    snapshot.secondsPerBoostedLiquidityOutsideUpperX128,
                snapshot.secondsOutsideLower - snapshot.secondsOutsideUpper
            );
        } else if (_slot0.tick < tickUpper) {
            SnapshotCumulativesInsideCache memory cache;
            cache.time = States._blockTimestamp();
            (
                cache.tickCumulative,
                cache.secondsPerLiquidityCumulativeX128,
                cache.secondsPerBoostedLiquidityCumulativeX128
            ) = observeSingle(
                states.observations,
                cache.time,
                0,
                _slot0.tick,
                _slot0.observationIndex,
                states.liquidity,
                states.boostedLiquidity,
                _slot0.observationCardinality
            );
            return (
                cache.tickCumulative -
                    snapshot.tickCumulativeLower -
                    snapshot.tickCumulativeUpper,
                cache.secondsPerLiquidityCumulativeX128 -
                    snapshot.secondsPerLiquidityOutsideLowerX128 -
                    snapshot.secondsPerLiquidityOutsideUpperX128,
                cache.secondsPerBoostedLiquidityCumulativeX128 -
                    snapshot.secondsPerBoostedLiquidityOutsideLowerX128 -
                    snapshot.secondsPerBoostedLiquidityOutsideUpperX128,
                cache.time -
                    snapshot.secondsOutsideLower -
                    snapshot.secondsOutsideUpper
            );
        } else {
            return (
                snapshot.tickCumulativeUpper - snapshot.tickCumulativeLower,
                snapshot.secondsPerLiquidityOutsideUpperX128 -
                    snapshot.secondsPerLiquidityOutsideLowerX128,
                snapshot.secondsPerBoostedLiquidityOutsideUpperX128 -
                    snapshot.secondsPerBoostedLiquidityOutsideLowerX128,
                snapshot.secondsOutsideUpper - snapshot.secondsOutsideLower
            );
        }
    }

    /// @notice Returns the seconds per liquidity and seconds inside a tick range for a period
    /// @dev This does not ensure the range is a valid range
    /// @param period The timestamp of the period
    /// @param tickLower The lower tick of the range
    /// @param tickUpper The upper tick of the range
    /// @return secondsPerLiquidityInsideX128 The snapshot of seconds per liquidity for the range
    /// @return secondsPerBoostedLiquidityInsideX128 The snapshot of seconds per boosted liquidity for the range
    function periodCumulativesInside(
        uint32 period,
        int24 tickLower,
        int24 tickUpper
    )
        external
        view
        returns (
            uint160 secondsPerLiquidityInsideX128,
            uint160 secondsPerBoostedLiquidityInsideX128
        )
    {
        States.PoolStates storage states = States.getStorage();

        TickInfo storage lower = states._ticks[tickLower];
        TickInfo storage upper = states._ticks[tickUpper];

        SnapShot memory snapshot;

        {
            int24 startTick = states.periods[period].startTick;
            uint256 previousPeriod = states.periods[period].previousPeriod;

            (
                snapshot.secondsPerLiquidityOutsideLowerX128,
                snapshot.secondsPerBoostedLiquidityOutsideLowerX128
            ) = (
                uint160(lower.periodSecondsPerLiquidityOutsideX128[period]),
                uint160(
                    lower.periodSecondsPerBoostedLiquidityOutsideX128[period]
                )
            );
            if (
                tickLower <= startTick &&
                snapshot.secondsPerLiquidityOutsideLowerX128 == 0
            ) {
                snapshot.secondsPerLiquidityOutsideLowerX128 = states
                    .periods[previousPeriod]
                    .endSecondsPerLiquidityPeriodX128;
            }

            // separate conditions because liquidity and boosted liquidity can be different
            if (
                tickLower <= startTick &&
                snapshot.secondsPerBoostedLiquidityOutsideLowerX128 == 0
            ) {
                snapshot.secondsPerBoostedLiquidityOutsideLowerX128 = states
                    .periods[previousPeriod]
                    .endSecondsPerBoostedLiquidityPeriodX128;
            }

            (
                snapshot.secondsPerLiquidityOutsideUpperX128,
                snapshot.secondsPerBoostedLiquidityOutsideUpperX128
            ) = (
                uint160(upper.periodSecondsPerLiquidityOutsideX128[period]),
                uint160(
                    upper.periodSecondsPerBoostedLiquidityOutsideX128[period]
                )
            );
            if (
                tickUpper <= startTick &&
                snapshot.secondsPerLiquidityOutsideUpperX128 == 0
            ) {
                snapshot.secondsPerLiquidityOutsideUpperX128 = states
                    .periods[previousPeriod]
                    .endSecondsPerLiquidityPeriodX128;
            }

            // separate conditions because liquidity and boosted liquidity can be different
            if (
                tickUpper <= startTick &&
                snapshot.secondsPerBoostedLiquidityOutsideUpperX128 == 0
            ) {
                snapshot.secondsPerBoostedLiquidityOutsideUpperX128 = states
                    .periods[previousPeriod]
                    .endSecondsPerBoostedLiquidityPeriodX128;
            }
        }

        int24 lastTick;
        uint256 currentPeriod = states.lastPeriod;
        {
            // if period is already finalized, use period's last tick, if not, use current tick
            if (currentPeriod > period) {
                lastTick = states.periods[period].lastTick;
            } else {
                lastTick = states.slot0.tick;
            }
        }

        if (lastTick < tickLower) {
            return (
                snapshot.secondsPerLiquidityOutsideLowerX128 -
                    snapshot.secondsPerLiquidityOutsideUpperX128,
                snapshot.secondsPerBoostedLiquidityOutsideLowerX128 -
                    snapshot.secondsPerBoostedLiquidityOutsideUpperX128
            );
        } else if (lastTick < tickUpper) {
            SnapshotCumulativesInsideCache memory cache;
            // if period's on-going, observeSingle, if finalized, use endSecondsPerLiquidityPeriodX128
            if (currentPeriod <= period) {
                cache.time = States._blockTimestamp();
                // limit to the end of period
                if (cache.time > currentPeriod * 1 weeks + 1 weeks) {
                    cache.time = uint32(currentPeriod * 1 weeks + 1 weeks);
                }

                Slot0 memory _slot0 = states.slot0;

                (
                    ,
                    cache.secondsPerLiquidityCumulativeX128,
                    cache.secondsPerBoostedLiquidityCumulativeX128
                ) = observeSingle(
                    states.observations,
                    cache.time,
                    0,
                    _slot0.tick,
                    _slot0.observationIndex,
                    states.liquidity,
                    states.boostedLiquidity,
                    _slot0.observationCardinality
                );
            } else {
                cache.secondsPerLiquidityCumulativeX128 = states
                    .periods[period]
                    .endSecondsPerLiquidityPeriodX128;
                cache.secondsPerBoostedLiquidityCumulativeX128 = states
                    .periods[period]
                    .endSecondsPerBoostedLiquidityPeriodX128;
            }

            return (
                cache.secondsPerLiquidityCumulativeX128 -
                    snapshot.secondsPerLiquidityOutsideLowerX128 -
                    snapshot.secondsPerLiquidityOutsideUpperX128,
                cache.secondsPerBoostedLiquidityCumulativeX128 -
                    snapshot.secondsPerBoostedLiquidityOutsideLowerX128 -
                    snapshot.secondsPerBoostedLiquidityOutsideUpperX128
            );
        } else {
            return (
                snapshot.secondsPerLiquidityOutsideUpperX128 -
                    snapshot.secondsPerLiquidityOutsideLowerX128,
                snapshot.secondsPerBoostedLiquidityOutsideUpperX128 -
                    snapshot.secondsPerBoostedLiquidityOutsideLowerX128
            );
        }
    }
}
