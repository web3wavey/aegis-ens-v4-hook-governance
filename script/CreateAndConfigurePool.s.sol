// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {HookGovernance} from "../src/HookGovernance.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";

contract CreateAndConfigurePool is Script {
    using PoolIdLibrary for PoolKey;

    address internal constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;

    address internal constant HOOK = 0x75d8a361edF13EBe1c20bc035103994437088A80;

    // ENSv2 Sepolia MockUSDC
    address internal constant MOCK_USDC = 0x768F42455A2D082E23ceeF7d51e5787C82d67a39;

    // Approximately 1 ETH = 3000 MockUSDC.
    //
    // ETH      = 18 decimals
    // MockUSDC = 6 decimals
    //
    // sqrtPriceX96 = sqrt(
    //     3000 * 10^6 / 10^18
    // ) * 2^96
    uint160 internal constant SQRT_PRICE_X96 = 4339505179874779489431521;

    function run() external returns (PoolId poolId) {
        uint256 ensResource = vm.envUint("ENS_RESOURCE");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(MOCK_USDC),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(HOOK)
        });

        poolId = key.toId();

        console2.log("Hook:", HOOK);
        console2.log("PoolManager:", POOL_MANAGER);
        console2.log("MockUSDC:", MOCK_USDC);
        console2.log("ENS resource:", ensResource);

        console2.log("PoolId:");
        console2.logBytes32(PoolId.unwrap(poolId));

        vm.startBroadcast();

        // Create the real Uniswap v4 pool.
        IPoolManager(POOL_MANAGER).initialize(key, SQRT_PRICE_X96);

        // Permanently associate this PoolId
        // with our stable ENSv2 resource.
        HookGovernance(HOOK).configurePool(poolId, ensResource);

        vm.stopBroadcast();

        console2.log("Pool initialized and ENS governance configured.");
    }
}
