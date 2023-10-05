// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
import "./FullMath.sol";
import "./SafeCast.sol";
import "./openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @title Math library for liquidity
library LiquidityMath {
    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        if (y < 0) {
            require((z = x - uint128(-y)) < x, "LS");
        } else {
            require((z = x + uint128(y)) >= x, "LA");
        }
    }

    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta256(
        uint256 x,
        int256 y
    ) internal pure returns (uint256 z) {
        if (y < 0) {
            require((z = x - uint256(-y)) < x, "LS");
        } else {
            require((z = x + uint256(y)) >= x, "LA");
        }
    }

    function calculateBoostedLiquidity(
        uint128 liquidity,
        int128 veRamAmount,
        int128 totalVeRamAmount
    ) internal pure returns (uint256 veRamRatio, uint128 boostedLiquidity) {
        veRamRatio = FullMath.mulDiv(
            uint256(uint128((veRamAmount))),
            1.5e18,
            totalVeRamAmount != 0 ? uint256(uint128(totalVeRamAmount)) : 1
        );

        // users acheive full boost if their veRAM is >=10% of the total veRAM attached to the pool
        // full boost is 1x original + 1.5x boost
        uint256 boostRatio = Math.min(veRamRatio * 10, 1.5e18); // veRamAmount and totalVeRamAmount can't go below 0

        boostedLiquidity = SafeCast.toUint128(
            FullMath.mulDiv(liquidity, boostRatio, 1e18)
        );
    }
}
