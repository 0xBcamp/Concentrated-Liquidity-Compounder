// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;
pragma abicoder v2;

import {console2} from "forge-std/Test.sol";

import "../interfaces/IRamsesV2Pool.sol";

import "../lib/LowGasSafeMath.sol";
import "../lib/SafeCast.sol";
import "../lib/Tick.sol";
import "../lib/TickBitmap.sol";
import "../lib/Position.sol";
import "../lib/Oracle.sol";
import "../lib/States.sol";
import "../lib/ProtocolActions.sol";

import "../lib/FullMath.sol";
import "../lib/FixedPoint128.sol";
import "../lib/TransferHelper.sol";
import "../lib/TickMath.sol";
import "../lib/LiquidityMath.sol";
import "../lib/SqrtPriceMath.sol";
import "../lib/SwapMath.sol";

import "../interfaces/pool/IRamsesV2PoolDeployer.sol";
import "../interfaces/IRamsesV2Factory.sol";
import "../interfaces/callback/IRamsesV2MintCallback.sol";
import "../interfaces/callback/IRamsesV2SwapCallback.sol";
import "../interfaces/callback/IRamsesV2FlashCallback.sol";

import "./../interfaces/IVotingEscrow.sol";
import "./../interfaces/IVoter.sol";

import "../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

contract RamsesV2Pool is Initializable, IRamsesV2Pool {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using TickBitmap for mapping(int16 => uint256);

    // To avoid stack-too-deep
    struct TokenAmounts {
        uint256 token0;
        uint256 token1;
    }

    // To avoid stack-too-deep
    struct TokenAmountInts {
        int256 token0;
        int256 token1;
    }

    bytes32 STATES_SLOT = keccak256("states.storage");

    /// @dev Mutually exclusive reentrancy protection into the pool to/from a method. This method also prevents entrance
    /// to a function before the pool is initialized. The reentrancy guard is required throughout the contract because
    /// we use balance checks to determine the payment status of interactions such as mint, swap and flash.
    modifier lock() {
        _lock();
        _;
        _unlock();
    }

    // separated for code size
    function _lock() internal {
        States.PoolStates storage states = States.getStorage();

        require(states.slot0.unlocked, "LOK");
        states.slot0.unlocked = false;
    }

    function _unlock() internal {
        States.getStorage().slot0.unlocked = true;
    }

    /// @dev Prevents calling a function from anyone except the address returned by IRamsesV2Factory#feeCollector()
    modifier onlyFeeCollector() {
        States.PoolStates storage states = States.getStorage();

        require(msg.sender == IRamsesV2Factory(states.factory).feeCollector());
        _;
    }

    /// @dev Advances period if it's a new week
    modifier advancePeriod() {
        _advancePeriod();
        _;
    }

    /// @dev Advances period if it's a new week
    function _advancePeriod() private {
        States.PoolStates storage states = States.getStorage();

        // if in new week, record lastTick for previous period
        // also record secondsPerLiquidityCumulativeX128 for the start of the new period
        uint256 _lastPeriod = states.lastPeriod;
        if ((States._blockTimestamp() / 1 weeks) != _lastPeriod) {
            Slot0 memory _slot0 = states.slot0;
            uint256 period = States._blockTimestamp() / 1 weeks;
            states.lastPeriod = period;

            // start new period in obervations
            (
                uint160 secondsPerLiquidityCumulativeX128,
                uint160 secondsPerBoostedLiquidityCumulativeX128,
                uint32 boostedInRange
            ) = Oracle.newPeriod(
                    states.observations,
                    _slot0.observationIndex,
                    period
                );

            // reset boostedLiquidity
            states.boostedLiquidity = 0;

            // record last tick and secondsPerLiquidityCumulativeX128 for old period
            states.periods[_lastPeriod].lastTick = _slot0.tick;
            states
                .periods[_lastPeriod]
                .endSecondsPerLiquidityPeriodX128 = secondsPerLiquidityCumulativeX128;
            states
                .periods[_lastPeriod]
                .endSecondsPerBoostedLiquidityPeriodX128 = secondsPerBoostedLiquidityCumulativeX128;
            states.periods[_lastPeriod].boostedInRange = boostedInRange;

            // record start tick and secondsPerLiquidityCumulativeX128 for new period
            PeriodInfo memory _newPeriod;

            _newPeriod.previousPeriod = uint32(_lastPeriod);
            _newPeriod.startTick = _slot0.tick;
            states.periods[period] = _newPeriod;
        }
    }

    /// @dev prevents implementation from being initialized later
    constructor() initializer() {}

    /// @dev initilializes
    function initialize(
        address _factory,
        address _nfpManager,
        address _veRam,
        address _voter,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) public initializer {
        States.PoolStates storage states = States.getStorage();

        states.factory = _factory;
        states.nfpManager = _nfpManager;
        states.veRam = _veRam;
        states.voter = _voter;
        states.token0 = _token0;
        states.token1 = _token1;
        states.fee = _fee;
        states.tickSpacing = _tickSpacing;

        states.maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(
            _tickSpacing
        );
    }

    /// View Functions

    // Get the address of the factory that created the pool
    ///  IRamsesV2PoolImmutables
    function factory() external view returns (address) {
        return States.getStorage().factory;
    }

    // Get the address of the NFP manager for the pool
    ///  IRamsesV2PoolImmutables
    function nfpManager() external view returns (address) {
        return States.getStorage().nfpManager;
    }

    // Get the address of the veRAM token for the pool
    ///  IRamsesV2PoolImmutables
    function veRam() external view returns (address) {
        return States.getStorage().veRam;
    }

    // Get the address of the voter contract for the pool
    ///  IRamsesV2PoolImmutables
    function voter() external view returns (address) {
        return States.getStorage().voter;
    }

    // Get the address of the first token in the pool
    ///  IRamsesV2PoolImmutables
    function token0() external view returns (address) {
        return States.getStorage().token0;
    }

    // Get the address of the second token in the pool
    ///  IRamsesV2PoolImmutables
    function token1() external view returns (address) {
        return States.getStorage().token1;
    }

    // Get the fee charged by the pool for swaps and liquidity provision
    ///  IRamsesV2PoolImmutables
    function fee() external view returns (uint24) {
        return States.getStorage().fee;
    }

    // Get the tick spacing for the pool
    ///  IRamsesV2PoolImmutables
    function tickSpacing() external view returns (int24) {
        return States.getStorage().tickSpacing;
    }

    // Get the maximum amount of liquidity that can be added to the pool at each tick
    ///  IRamsesV2PoolImmutables
    function maxLiquidityPerTick() external view returns (uint128) {
        return States.getStorage().maxLiquidityPerTick;
    }

    ///  IRamsesV2PoolState
    function readStorage(
        bytes32[] calldata slots
    ) external view returns (bytes32[] memory returnData) {
        uint256 slotsLength = slots.length;
        returnData = new bytes32[](slotsLength);

        for (uint256 i = 0; i < slotsLength; ++i) {
            bytes32 slot = slots[i];
            bytes32 _returnData;
            assembly {
                _returnData := sload(slot)
            }
            returnData[i] = _returnData;
        }
    }

    // Get the Slot0 struct for the pool
    ///  IRamsesV2PoolState
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        Slot0 memory _slot0 = States.getStorage().slot0;

        return (
            _slot0.sqrtPriceX96,
            _slot0.tick,
            _slot0.observationIndex,
            _slot0.observationCardinality,
            _slot0.observationCardinalityNext,
            _slot0.feeProtocol,
            _slot0.unlocked
        );
    }

    // Get the PeriodInfo struct for a given period in the pool
    ///  IRamsesV2PoolState
    function periods(
        uint256 period
    )
        external
        view
        returns (
            uint32 previousPeriod,
            int24 startTick,
            int24 lastTick,
            uint160 endSecondsPerLiquidityPeriodX128,
            uint160 endSecondsPerBoostedLiquidityPeriodX128,
            uint32 boostedInRange
        )
    {
        PeriodInfo memory periodData = States.getStorage().periods[period];
        return (
            periodData.previousPeriod,
            periodData.startTick,
            periodData.lastTick,
            periodData.endSecondsPerLiquidityPeriodX128,
            periodData.endSecondsPerBoostedLiquidityPeriodX128,
            periodData.boostedInRange
        );
    }

    // Get the index of the last period in the pool
    ///  IRamsesV2PoolState
    function lastPeriod() external view returns (uint256) {
        return States.getStorage().lastPeriod;
    }

    // Get the accumulated fee growth for the first token in the pool
    ///  IRamsesV2PoolState
    function feeGrowthGlobal0X128() external view returns (uint256) {
        return States.getStorage().feeGrowthGlobal0X128;
    }

    // Get the accumulated fee growth for the second token in the pool
    ///  IRamsesV2PoolState
    function feeGrowthGlobal1X128() external view returns (uint256) {
        return States.getStorage().feeGrowthGlobal1X128;
    }

    // Get the protocol fees accumulated by the pool
    ///  IRamsesV2PoolState
    function protocolFees()
        external
        view
        returns (uint128 token0, uint128 token1)
    {
        ProtocolFees memory protocolFeesData = States.getStorage().protocolFees;
        return (protocolFeesData.token0, protocolFeesData.token1);
    }

    // Get the total liquidity of the pool
    ///  IRamsesV2PoolState
    function liquidity() external view returns (uint128) {
        return States.getStorage().liquidity;
    }

    // Get the boosted liquidity of the pool
    ///  IRamsesV2PoolState
    function boostedLiquidity() external view returns (uint128) {
        return States.getStorage().boostedLiquidity;
    }

    // Get the ticks of the pool
    ///  IRamsesV2PoolState
    function ticks(
        int24 tick
    )
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint128 boostedLiquidityGross,
            int128 boostedLiquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {
        uint256 period = States._blockTimestamp() / 1 weeks;
        TickInfo storage tickData = States.getStorage()._ticks[tick];
        liquidityGross = tickData.liquidityGross;
        liquidityNet = tickData.liquidityNet;
        boostedLiquidityGross = tickData.boostedLiquidityGross[period];
        boostedLiquidityNet = tickData.boostedLiquidityNet[period];
        feeGrowthOutside0X128 = tickData.feeGrowthOutside0X128;
        feeGrowthOutside1X128 = tickData.feeGrowthOutside1X128;
        tickCumulativeOutside = tickData.tickCumulativeOutside;
        secondsPerLiquidityOutsideX128 = tickData
            .secondsPerLiquidityOutsideX128;
        secondsOutside = tickData.secondsOutside;
        initialized = tickData.initialized;
    }

    // Get the tick bitmap of the pool
    ///  IRamsesV2PoolState
    function tickBitmap(int16 tick) external view returns (uint256) {
        return States.getStorage().tickBitmap[tick];
    }

    // Get information about a specific position in the pool
    ///  IRamsesV2PoolState
    function positions(
        bytes32 key
    )
        external
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1,
            uint256 attachedVeRamId
        )
    {
        PositionInfo memory positionData = States.getStorage().positions[key];
        return (
            positionData.liquidity,
            positionData.feeGrowthInside0LastX128,
            positionData.feeGrowthInside1LastX128,
            positionData.tokensOwed0,
            positionData.tokensOwed1,
            positionData.attachedVeRamId
        );
    }

    // Get the boost information for a specific period
    ///  IRamsesV2PoolState
    function boostInfos(
        uint256 period
    )
        external
        view
        returns (uint128 totalBoostAmount, int128 totalVeRamAmount)
    {
        PeriodBoostInfo storage periodBoostInfoData = States
            .getStorage()
            .boostInfos[period];
        return (
            periodBoostInfoData.totalBoostAmount,
            periodBoostInfoData.totalVeRamAmount
        );
    }

    // Get the boost information for a specific position at a period
    ///  IRamsesV2PoolState
    function boostInfos(
        uint256 period,
        bytes32 key
    )
        external
        view
        returns (
            uint128 boostAmount,
            int128 veRamAmount,
            int256 secondsDebtX96,
            int256 boostedSecondsDebtX96
        )
    {
        BoostInfo memory boostInfo = States
            .getStorage()
            .boostInfos[period]
            .positions[key];
        return (
            boostInfo.boostAmount,
            boostInfo.veRamAmount,
            boostInfo.secondsDebtX96,
            boostInfo.boostedSecondsDebtX96
        );
    }

    // Get the period seconds debt of a specific position
    ///  IRamsesV2PoolState
    function positionPeriodDebt(
        uint256 period,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    )
        external
        view
        returns (int256 secondsDebtX96, int256 boostedSecondsDebtX96)
    {
        States.PoolStates storage states = States.getStorage();
        BoostInfo storage position = Position.get(
            states.boostInfos[period],
            owner,
            index,
            tickLower,
            tickUpper
        );

        secondsDebtX96 = position.secondsDebtX96;
        boostedSecondsDebtX96 = position.boostedSecondsDebtX96;

        return (secondsDebtX96, boostedSecondsDebtX96);
    }

    // Get the period seconds in range of a specific position
    ///  IRamsesV2PoolState
    function positionPeriodSecondsInRange(
        uint256 period,
        address owner,
        uint256 index,
        int24 tickLower,
        int24 tickUpper
    )
        external
        view
        returns (
            uint256 periodSecondsInsideX96,
            uint256 periodBoostedSecondsInsideX96
        )
    {
        (periodSecondsInsideX96, periodBoostedSecondsInsideX96) = Position
            .positionPeriodSecondsInRange(
                Position.PositionPeriodSecondsInRangeParams({
                    period: period,
                    owner: owner,
                    index: index,
                    tickLower: tickLower,
                    tickUpper: tickUpper
                })
            );

        return (periodSecondsInsideX96, periodBoostedSecondsInsideX96);
    }

    // Get the observations recorded by the pool
    ///  IRamsesV2PoolState
    function observations(
        uint256 index
    )
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized,
            uint160 secondsPerBoostedLiquidityPeriodX128
        )
    {
        Observation memory observationData = States.getStorage().observations[
            index
        ];
        return (
            observationData.blockTimestamp,
            observationData.tickCumulative,
            observationData.secondsPerLiquidityCumulativeX128,
            observationData.initialized,
            observationData.secondsPerBoostedLiquidityPeriodX128
        );
    }

    ///  IRamsesV2PoolDerivedState
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
        // check ticks
        require(tickLower < tickUpper, "TLU");
        require(tickLower >= TickMath.MIN_TICK, "TLM");
        require(tickUpper <= TickMath.MAX_TICK, "TUM");

        return Oracle.snapshotCumulativesInside(tickLower, tickUpper);
    }

    ///  IRamsesV2PoolDerivedState
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
        return Oracle.periodCumulativesInside(period, tickLower, tickUpper);
    }

    ///  IRamsesV2PoolDerivedState
    function observe(
        uint32[] calldata secondsAgos
    )
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s,
            uint160[] memory secondsPerBoostedLiquidityPeriodX128s
        )
    {
        States.PoolStates storage states = States.getStorage();

        return
            Oracle.observe(
                states.observations,
                States._blockTimestamp(),
                secondsAgos,
                states.slot0.tick,
                states.slot0.observationIndex,
                states.liquidity,
                states.boostedLiquidity,
                states.slot0.observationCardinality
            );
    }

    ///  IRamsesV2PoolActions
    function increaseObservationCardinalityNext(
        uint16 observationCardinalityNext
    ) external lock {
        States.PoolStates storage states = States.getStorage();

        uint16 observationCardinalityNextOld = states
            .slot0
            .observationCardinalityNext; // for the event
        uint16 observationCardinalityNextNew = Oracle.grow(
            states.observations,
            observationCardinalityNextOld,
            observationCardinalityNext
        );
        states.slot0.observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew)
            emit IncreaseObservationCardinalityNext(
                observationCardinalityNextOld,
                observationCardinalityNextNew
            );
    }

    ///  IRamsesV2PoolActions
    /// @dev not locked because it initializes unlocked
    function initialize(uint160 sqrtPriceX96) external {
        States.PoolStates storage states = States.getStorage();

        require(states.slot0.sqrtPriceX96 == 0, "AI");

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = Oracle.initialize(
            states.observations,
            0
        );

        _advancePeriod();

        uint8 feeProtocol = IRamsesV2Factory(states.factory).poolFeeProtocol(
            address(this)
        );

        states.slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: feeProtocol,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
        emit SetFeeProtocol(0, 0, feeProtocol % 16, feeProtocol >> 4);
    }

    ///  IRamsesV2PoolActions
    /// @dev lock and advancePeriod is applied indirectly in mint()
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        console2.log(">>>>>>>>>>> Recipient: ", recipient);
        return
            mint(
                recipient,
                0,
                tickLower,
                tickUpper,
                amount,
                type(uint256).max,
                data
            );
    }

    ///  IRamsesV2PoolActions
    function mint(
        address recipient,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 veRamTokenId,
        bytes calldata data
    ) public lock advancePeriod returns (uint256 amount0, uint256 amount1) {
        console2.log(">>>>>>>>>>> Recipient: ", recipient);
        console2.log(">>>>>>>>>>> Sender: ", msg.sender);
        console2.log(amount);
        require(amount > 0);
        if (veRamTokenId != type(uint256).max) {
            require(recipient == msg.sender);
        }

        TokenAmountInts memory amountInt;
        console2.log(">>>>>>>>>1  Modyfing position... ");
        (, amountInt.token0, amountInt.token1) = Position._modifyPosition(
            Position.ModifyPositionParams({
                owner: recipient,
                index: index,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: (int128(amount)),
                veRamTokenId: veRamTokenId
            })
        );
        console2.log(">>>>>>>>>2  After position... ");
        amount0 = uint256(amountInt.token0);
        amount1 = uint256(amountInt.token1);

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = States.balance0();
        if (amount1 > 0) balance1Before = States.balance1();
        IRamsesV2MintCallback(msg.sender).ramsesV2MintCallback(
            amount0,
            amount1,
            data
        );
        if (amount0 > 0)
            require(balance0Before.add(amount0) <= States.balance0(), "M0");
        if (amount1 > 0)
            require(balance1Before.add(amount1) <= States.balance1(), "M1");

        emit Mint(
            msg.sender,
            recipient,
            tickLower,
            tickUpper,
            amount,
            amount0,
            amount1
        );
    }

    ///  IRamsesV2PoolActions
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1) {
        return
            collect(
                recipient,
                0,
                tickLower,
                tickUpper,
                amount0Requested,
                amount1Requested
            );
    }

    ///  IRamsesV2PoolActions
    function collect(
        address recipient,
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public lock returns (uint128 amount0, uint128 amount1) {
        States.PoolStates storage states = States.getStorage();

        // we don't need to checkTicks here, because invalid positions will never have non-zero tokensOwed{0,1}
        PositionInfo storage position = Position.get(
            states.positions,
            msg.sender,
            index,
            tickLower,
            tickUpper
        );

        amount0 = amount0Requested > position.tokensOwed0
            ? position.tokensOwed0
            : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1
            ? position.tokensOwed1
            : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(states.token0, recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(states.token1, recipient, amount1);
        }

        emit Collect(
            msg.sender,
            recipient,
            tickLower,
            tickUpper,
            amount0,
            amount1
        );
    }

    ///  IRamsesV2PoolActions
    /// @dev lock and advancePeriod is applied indirectly in burn()
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        return burn(0, tickLower, tickUpper, amount, type(uint256).max);
    }

    /// @dev lock and advancePeriod is applied indirectly in burn()
    ///  IRamsesV2PoolActions
    function burn(
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        return burn(index, tickLower, tickUpper, amount, type(uint256).max);
    }

    ///  IRamsesV2PoolActions
    function burn(
        uint256 index,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        uint256 veRamTokenId
    ) public lock advancePeriod returns (uint256 amount0, uint256 amount1) {
        (
            PositionInfo storage position,
            int256 amount0Int,
            int256 amount1Int
        ) = Position._modifyPosition(
                Position.ModifyPositionParams({
                    owner: msg.sender,
                    index: index,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -(int128(amount)),
                    veRamTokenId: veRamTokenId
                })
            );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    struct SwapCache {
        // the protocol fee for the input token
        uint8 feeProtocol;
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // boosted liquidity at the beginning of the swap
        uint128 boostedLiquidityStart;
        // the timestamp of the current block
        uint32 blockTimestamp;
        // the current value of the tick accumulator, computed only if we cross an initialized tick
        int56 tickCumulative;
        // the current value of seconds per liquidity accumulator, computed only if we cross an initialized tick
        uint160 secondsPerLiquidityCumulativeX128;
        // the current value of seconds per boosted liquidity accumulator, computed only if we cross an initialized tick
        uint160 secondsPerBoostedLiquidityPeriodX128;
        // whether we've computed and cached the above two accumulators
        bool computedLatestObservation;
        // whether the swap has exactInput
        bool exactInput;
        // timestamp of the previous period
        uint32 previousPeriod;
    }

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // amount of input token paid as protocol fee
        uint128 protocolFee;
        // the current liquidity in range
        uint128 liquidity;
        // the current boosted liquidity in range
        uint128 boostedLiquidity;
        // seconds per liquidity at the end of the previous period
        uint256 endSecondsPerLiquidityPeriodX128;
        // seconds per boosted liquidity at the end of the previous period
        uint256 endSecondsPerBoostedLiquidityPeriodX128;
        // starting tick of the current period
        int24 periodStartTick;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    struct CrossCache {
        int128 liquidityNet;
        int128 boostedLiquidityNet;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
    }

    ///  IRamsesV2PoolActions
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external advancePeriod returns (int256 amount0, int256 amount1) {
        States.PoolStates storage states = States.getStorage();

        require(amountSpecified != 0, "AS");

        Slot0 memory slot0Start = states.slot0;

        require(slot0Start.unlocked, "LOK");
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 &&
                    sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 &&
                    sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            "SPL"
        );

        states.slot0.unlocked = false;

        SwapCache memory cache;
        SwapState memory state;

        {
            uint256 period = States._blockTimestamp() / 1 weeks;

            cache = SwapCache({
                liquidityStart: states.liquidity,
                boostedLiquidityStart: states.boostedLiquidity,
                blockTimestamp: States._blockTimestamp(),
                feeProtocol: zeroForOne
                    ? (slot0Start.feeProtocol % 16)
                    : (slot0Start.feeProtocol >> 4),
                secondsPerLiquidityCumulativeX128: 0,
                secondsPerBoostedLiquidityPeriodX128: 0,
                tickCumulative: 0,
                computedLatestObservation: false,
                exactInput: amountSpecified > 0,
                previousPeriod: states.periods[period].previousPeriod
            });

            state = SwapState({
                amountSpecifiedRemaining: amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: slot0Start.sqrtPriceX96,
                tick: slot0Start.tick,
                feeGrowthGlobalX128: zeroForOne
                    ? states.feeGrowthGlobal0X128
                    : states.feeGrowthGlobal1X128,
                protocolFee: 0,
                liquidity: cache.liquidityStart,
                boostedLiquidity: cache.boostedLiquidityStart,
                endSecondsPerLiquidityPeriodX128: states
                    .periods[cache.previousPeriod]
                    .endSecondsPerLiquidityPeriodX128,
                endSecondsPerBoostedLiquidityPeriodX128: states
                    .periods[cache.previousPeriod]
                    .endSecondsPerBoostedLiquidityPeriodX128,
                periodStartTick: states.periods[period].startTick
            });
        }

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (
            state.amountSpecifiedRemaining != 0 &&
            state.sqrtPriceX96 != sqrtPriceLimitX96
        ) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) = TickBitmap
                .nextInitializedTickWithinOneWord(
                    states.tickBitmap,
                    state.tick,
                    states.tickSpacing,
                    zeroForOne
                );

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            (
                state.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (
                    zeroForOne
                        ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                )
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                states.fee
            );

            if (cache.exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn +
                    step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(
                    step.amountOut.toInt256()
                );
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add(
                    (step.amountIn + step.feeAmount).toInt256()
                );
            }

            // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (cache.feeProtocol > 0) {
                uint256 delta = (step.feeAmount *
                    (cache.feeProtocol * 5 + 50)) / 100;
                step.feeAmount -= delta;
                state.protocolFee += uint128(delta);
            }

            // update global fee tracker
            if (state.liquidity > 0)
                state.feeGrowthGlobalX128 += FullMath.mulDiv(
                    step.feeAmount,
                    FixedPoint128.Q128,
                    state.liquidity
                );

            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    // check for the placeholder value, which we replace with the actual value the first time the swap
                    // crosses an initialized tick
                    if (!cache.computedLatestObservation) {
                        (
                            cache.tickCumulative,
                            cache.secondsPerLiquidityCumulativeX128,
                            cache.secondsPerBoostedLiquidityPeriodX128
                        ) = Oracle.observeSingle(
                            states.observations,
                            cache.blockTimestamp,
                            0,
                            slot0Start.tick,
                            slot0Start.observationIndex,
                            cache.liquidityStart,
                            cache.boostedLiquidityStart,
                            slot0Start.observationCardinality
                        );
                        cache.computedLatestObservation = true;
                    }
                    CrossCache memory crossCache; // stack too deep

                    if (zeroForOne) {
                        // yes, one uses state and the other uses states, this is not a typo
                        crossCache.feeGrowthGlobal0X128 = state
                            .feeGrowthGlobalX128;
                        crossCache.feeGrowthGlobal1X128 = states
                            .feeGrowthGlobal1X128;
                    } else {
                        crossCache.feeGrowthGlobal0X128 = states
                            .feeGrowthGlobal0X128;
                        crossCache.feeGrowthGlobal1X128 = state
                            .feeGrowthGlobalX128;
                    }
                    (
                        crossCache.liquidityNet,
                        crossCache.boostedLiquidityNet
                    ) = Tick.cross(
                        states._ticks,
                        Tick.CrossParams(
                            step.tickNext,
                            crossCache.feeGrowthGlobal0X128,
                            crossCache.feeGrowthGlobal1X128,
                            cache.secondsPerLiquidityCumulativeX128,
                            cache.secondsPerBoostedLiquidityPeriodX128,
                            state.endSecondsPerLiquidityPeriodX128,
                            state.endSecondsPerBoostedLiquidityPeriodX128,
                            state.periodStartTick,
                            cache.tickCumulative,
                            cache.blockTimestamp
                        )
                    );
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    if (zeroForOne) {
                        crossCache.liquidityNet = -crossCache.liquidityNet;
                        crossCache.boostedLiquidityNet = -crossCache
                            .boostedLiquidityNet;
                    }

                    state.liquidity = LiquidityMath.addDelta(
                        state.liquidity,
                        crossCache.liquidityNet
                    );
                    state.boostedLiquidity = LiquidityMath.addDelta(
                        state.boostedLiquidity,
                        crossCache.boostedLiquidityNet
                    );
                }

                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // update tick and write an oracle entry if the tick change
        if (state.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = Oracle
                .write(
                    states.observations,
                    slot0Start.observationIndex,
                    cache.blockTimestamp,
                    slot0Start.tick,
                    cache.liquidityStart,
                    cache.boostedLiquidityStart,
                    slot0Start.observationCardinality,
                    slot0Start.observationCardinalityNext
                );
            (
                states.slot0.sqrtPriceX96,
                states.slot0.tick,
                states.slot0.observationIndex,
                states.slot0.observationCardinality
            ) = (
                state.sqrtPriceX96,
                state.tick,
                observationIndex,
                observationCardinality
            );
        } else {
            // otherwise just update the price
            states.slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // update liquidity if it changed
        if (cache.liquidityStart != state.liquidity) {
            states.liquidity = state.liquidity;
        }

        // update if boosted changed, need a separate check because boosted can change without liquidity changing
        if (cache.boostedLiquidityStart != state.boostedLiquidity) {
            states.boostedLiquidity = state.boostedLiquidity;
        }

        // update fee growth global and, if necessary, protocol fees
        // overflow is acceptable, protocol has to withdraw before it hits type(uint128).max fees
        if (zeroForOne) {
            states.feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0)
                states.protocolFees.token0 += state.protocolFee;
        } else {
            states.feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0)
                states.protocolFees.token1 += state.protocolFee;
        }

        (amount0, amount1) = zeroForOne == cache.exactInput
            ? (
                amountSpecified - state.amountSpecifiedRemaining,
                state.amountCalculated
            )
            : (
                state.amountCalculated,
                amountSpecified - state.amountSpecifiedRemaining
            );

        // do the transfers and collect payment
        if (zeroForOne) {
            if (amount1 < 0)
                TransferHelper.safeTransfer(
                    states.token1,
                    recipient,
                    uint256(-amount1)
                );

            uint256 balance0Before = States.balance0();
            IRamsesV2SwapCallback(msg.sender).ramsesV2SwapCallback(
                amount0,
                amount1,
                data
            );
            require(
                balance0Before.add(uint256(amount0)) <= States.balance0(),
                "IIA"
            );
        } else {
            if (amount0 < 0)
                TransferHelper.safeTransfer(
                    states.token0,
                    recipient,
                    uint256(-amount0)
                );

            uint256 balance1Before = States.balance1();
            IRamsesV2SwapCallback(msg.sender).ramsesV2SwapCallback(
                amount0,
                amount1,
                data
            );
            require(
                balance1Before.add(uint256(amount1)) <= States.balance1(),
                "IIA"
            );
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            state.sqrtPriceX96,
            state.liquidity,
            state.tick
        );
        states.slot0.unlocked = true;
    }

    ///  IRamsesV2PoolActions
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external lock {
        States.PoolStates storage states = States.getStorage();

        uint128 _liquidity = states.liquidity;
        require(_liquidity > 0, "L");

        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, states.fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, states.fee, 1e6);
        uint256 balance0Before = States.balance0();
        uint256 balance1Before = States.balance1();

        if (amount0 > 0)
            TransferHelper.safeTransfer(states.token0, recipient, amount0);
        if (amount1 > 0)
            TransferHelper.safeTransfer(states.token1, recipient, amount1);

        IRamsesV2FlashCallback(msg.sender).ramsesV2FlashCallback(
            fee0,
            fee1,
            data
        );

        TokenAmounts memory balanceAfter;
        balanceAfter.token0 = States.balance0();
        balanceAfter.token1 = States.balance1();

        require(balance0Before.add(fee0) <= balanceAfter.token0, "F0");
        require(balance1Before.add(fee1) <= balanceAfter.token1, "F1");

        // sub is safe because we know balanceAfter is gt balanceBefore by at least fee
        TokenAmounts memory paid;
        paid.token0 = balanceAfter.token0 - balance0Before;
        paid.token1 = balanceAfter.token1 - balance1Before;

        if (paid.token0 > 0) {
            uint8 feeProtocol0 = states.slot0.feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid.token0 / feeProtocol0;
            if (uint128(fees0) > 0)
                states.protocolFees.token0 += uint128(fees0);
            states.feeGrowthGlobal0X128 += FullMath.mulDiv(
                paid.token0 - fees0,
                FixedPoint128.Q128,
                _liquidity
            );
        }
        if (paid.token1 > 0) {
            uint8 feeProtocol1 = states.slot0.feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid.token1 / feeProtocol1;
            if (uint128(fees1) > 0)
                states.protocolFees.token1 += uint128(fees1);
            states.feeGrowthGlobal1X128 += FullMath.mulDiv(
                paid.token1 - fees1,
                FixedPoint128.Q128,
                _liquidity
            );
        }

        emit Flash(
            msg.sender,
            recipient,
            amount0,
            amount1,
            paid.token0,
            paid.token1
        );
    }

    ///  IRamsesV2PoolOwnerActions
    function setFeeProtocol() external lock {
        ProtocolActions.setFeeProtocol();
    }

    ///  IRamsesV2PoolOwnerActions
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    )
        external
        lock
        onlyFeeCollector
        returns (uint128 amount0, uint128 amount1)
    {
        return
            ProtocolActions.collectProtocol(
                recipient,
                amount0Requested,
                amount1Requested
            );
    }
}
