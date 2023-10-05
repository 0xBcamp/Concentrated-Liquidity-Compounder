// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./States.sol";
import "./TransferHelper.sol";
import "../interfaces/IRamsesV2Factory.sol";
import "../interfaces/pool/IRamsesV2PoolOwnerActions.sol";
import "../interfaces/pool/IRamsesV2PoolEvents.sol";

library ProtocolActions {
    /// @notice Emitted when the protocol fee is changed by the pool
    /// @param feeProtocol0Old The previous value of the token0 protocol fee
    /// @param feeProtocol1Old The previous value of the token1 protocol fee
    /// @param feeProtocol0New The updated value of the token0 protocol fee
    /// @param feeProtocol1New The updated value of the token1 protocol fee
    event SetFeeProtocol(
        uint8 feeProtocol0Old,
        uint8 feeProtocol1Old,
        uint8 feeProtocol0New,
        uint8 feeProtocol1New
    );

    /// @notice Emitted when the collected protocol fees are withdrawn by the factory owner
    /// @param sender The address that collects the protocol fees
    /// @param recipient The address that receives the collected protocol fees
    /// @param amount0 The amount of token0 protocol fees that is withdrawn
    /// @param amount0 The amount of token1 protocol fees that is withdrawn
    event CollectProtocol(
        address indexed sender,
        address indexed recipient,
        uint128 amount0,
        uint128 amount1
    );

    /// @notice Set the protocol's % share of the fees
    /// @dev Fees start at 50%, with 5% increments
    function setFeeProtocol() external {
        States.PoolStates storage states = States.getStorage();

        uint8 feeProtocolOld = states.slot0.feeProtocol;

        uint8 feeProtocol = IRamsesV2Factory(states.factory).poolFeeProtocol(
            address(this)
        );

        if (feeProtocol != feeProtocolOld) {
            states.slot0.feeProtocol = feeProtocol;

            emit SetFeeProtocol(
                feeProtocolOld % 16,
                feeProtocolOld >> 4,
                feeProtocol % 16,
                feeProtocol >> 4
            );
        }
    }

    /// @notice Collect the protocol fee accrued to the pool
    /// @param recipient The address to which collected protocol fees should be sent
    /// @param amount0Requested The maximum amount of token0 to send, can be 0 to collect fees in only token1
    /// @param amount1Requested The maximum amount of token1 to send, can be 0 to collect fees in only token0
    /// @return amount0 The protocol fee collected in token0
    /// @return amount1 The protocol fee collected in token1
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1) {
        States.PoolStates storage states = States.getStorage();

        amount0 = amount0Requested > states.protocolFees.token0
            ? states.protocolFees.token0
            : amount0Requested;
        amount1 = amount1Requested > states.protocolFees.token1
            ? states.protocolFees.token1
            : amount1Requested;

        if (amount0 > 0) {
            if (amount0 == states.protocolFees.token0) amount0--; // ensure that the slot is not cleared, for gas savings
            states.protocolFees.token0 -= amount0;
            TransferHelper.safeTransfer(states.token0, recipient, amount0);
        }
        if (amount1 > 0) {
            if (amount1 == states.protocolFees.token1) amount1--; // ensure that the slot is not cleared, for gas savings
            states.protocolFees.token1 -= amount1;
            TransferHelper.safeTransfer(states.token1, recipient, amount1);
        }

        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}
