// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IRewardsDistributor.sol";

interface IMinter {
    function update_period() external returns (uint);

    function active_period() external view returns (uint);

    function _rewards_distributor() external view returns (IRewardsDistributor);
}
