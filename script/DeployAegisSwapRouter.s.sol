// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {AegisSwapRouter} from "../src/AegisSwapRouter.sol";

contract DeployAegisSwapRouter is Script {
    function run() external returns (AegisSwapRouter router) {
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));

        vm.startBroadcast();

        router = new AegisSwapRouter(manager);

        vm.stopBroadcast();

        console2.log("AEGIS_SWAP_ROUTER:", address(router));
    }
}
