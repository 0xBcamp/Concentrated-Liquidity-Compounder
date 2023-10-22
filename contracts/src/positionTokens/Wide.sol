//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../interfaces/PositionToken.sol";

contract Wide is PositionToken {
    uint8 rangePercentageTolerance = 10;

    constructor() ERC20("Wide", "WIDE") {
        owner = msg.sender;
    }

    function rangePercentage() external view override returns (uint8) {
        return rangePercentageTolerance;
    }
}
