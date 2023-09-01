//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/IRamsesV2Pool.sol";
import "../../interfaces/ISwapRouter.sol";
import "../../interfaces/IRamsesV2Factory.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/ERCStandards/IERC20MintableBurnable.sol";

interface ICLExecutor {
    enum ranges {
        NARROW,
        MID,
        WIDE,
        MAX
    }
}
