// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/ClExecutor.sol";
import {Narrow} from "../src/positionTokens/Narrow.sol";
import {Mid} from "../src/positionTokens/Mid.sol";
import {Wide} from "../src/positionTokens/Wide.sol";

contract MyScript is Script {

    ClExecutor clExecutor;
    Narrow narrow;
    Mid mid;
    Wide wide;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        narrow = new Narrow();
        mid = new Mid();
        wide = new Wide();
        address ROUTER_V2 = 0xAA23611badAFB62D37E7295A682D21960ac85A90;

        clExecutor = new ClExecutor(ROUTER_V2,address(narrow), address(mid),address(wide));

        vm.stopBroadcast();
    }
}