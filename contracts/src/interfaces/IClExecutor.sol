//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/IRamsesV2Pool.sol";
import "../../interfaces/ISwapRouter.sol";
import "../../interfaces/IRamsesV2Factory.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/IVotingEscrow.sol";
import "../../interfaces/IVoter.sol";
import "../interfaces/IPositionToken.sol";
import "../../interfaces/IMinter.sol";
import "../../interfaces/ERCStandards/IWeth.sol";
import "../../interfaces/IRamsesV2GaugeFactory.sol";
import "../../interfaces/IGaugeV2.sol";
import "../../lib/TickMath.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

interface IClExecutor {
    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    enum ranges {
        NARROW,
        MID,
        WIDE,
        MAX
    }

    error WrongRangesPassed(ranges);
    error PositionNotFound();
}
