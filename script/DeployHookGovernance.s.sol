// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {HookGovernance} from "../src/HookGovernance.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {IPermissionedRegistry} from "@ensdomains/contracts-v2/registry/interfaces/IPermissionedRegistry.sol";

import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";

contract DeployHookGovernance is Script {
    // Canonical CREATE2 deployer used by Foundry deployment scripts.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    // Uniswap v4 PoolManager - Ethereum Sepolia.
    address internal constant SEPOLIA_POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;

    function run() external returns (HookGovernance hook) {
        address ensRegistry = vm.envAddress("ETH_REGISTRY");

        address configurator = vm.envAddress("POOL_CONFIGURATOR");

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG) | uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG)
            | uint160(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG);

        bytes memory constructorArgs =
            abi.encode(IPoolManager(SEPOLIA_POOL_MANAGER), IPermissionedRegistry(ensRegistry), configurator);

        (address predictedHookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(HookGovernance).creationCode, constructorArgs);

        console2.log("Pool configurator:", configurator);

        console2.log("Predicted hook:", predictedHookAddress);

        console2.log("CREATE2 salt:");
        console2.logBytes32(salt);

        vm.startBroadcast();

        hook = new HookGovernance{salt: salt}(
            IPoolManager(SEPOLIA_POOL_MANAGER), IPermissionedRegistry(ensRegistry), configurator
        );

        vm.stopBroadcast();

        require(address(hook) == predictedHookAddress, "Unexpected hook address");

        require((uint160(address(hook)) & uint160(Hooks.ALL_HOOK_MASK)) == flags, "Invalid hook permissions");

        console2.log("HookGovernance deployed:", address(hook));

        console2.log("ENS registry:", ensRegistry);
    }
}
