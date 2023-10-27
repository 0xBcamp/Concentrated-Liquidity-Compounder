//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../interfaces/PositionToken.sol";

contract Mid is PositionToken {
    uint8 rangePercentageTolerance = 2;

    constructor() ERC20("Mid", "MID") {
        owner = msg.sender;
    }

    function rangePercentage() external view override returns (uint8) {
        return rangePercentageTolerance;
    }
}
