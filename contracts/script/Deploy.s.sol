// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PRISMRegistry} from "../src/PRISMRegistry.sol";

contract Deploy is Script {
    function run() external returns (PRISMRegistry reg) {
        // Usage:
        // forge script script/Deploy.s.sol:Deploy --rpc-url $RPC --private-key $PK --broadcast
        address issuer = vm.envAddress("PRISM_ISSUER");
        uint64 ttl = uint64(vm.envUint("PRISM_TTL"));
        if (ttl == 0) ttl = uint64(7 days);

        vm.startBroadcast();
        reg = new PRISMRegistry(issuer, ttl);
        vm.stopBroadcast();
    }
}
