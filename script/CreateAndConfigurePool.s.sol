// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";

import {Currency} from "v4-core/types/Currency.sol";

interface IHookGovernance {
    function configurePool(PoolId poolId, uint256 ensResource) external;
}

contract CreateAndConfigurePool is Script {
    using PoolIdLibrary for PoolKey;

    // ~1 ETH = 3000 MockUSDC
    // ETH has 18 decimals, MockUSDC has 6.
    uint160 internal constant SQRT_PRICE_X96 = 4339505179874779489431521;

    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_SPACING = 60;

    function run() external returns (PoolId poolId) {
        address poolManager = vm.envAddress("POOL_MANAGER");

        address hook = vm.envAddress("HOOK");

        address mockUsdc = vm.envAddress("MOCK_USDC");

        uint256 ensResource = vm.envUint("ENS_RESOURCE");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(mockUsdc),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        poolId = key.toId();

        console2.log("PoolManager:", poolManager);

        console2.log("Hook:", hook);

        console2.log("MockUSDC:", mockUsdc);

        console2.log("ENS resource:", ensResource);

        console2.log("Pool ID:");

        console2.logBytes32(PoolId.unwrap(poolId));

        vm.startBroadcast();

        IPoolManager(poolManager).initialize(key, SQRT_PRICE_X96);

        IHookGovernance(hook).configurePool(poolId, ensResource);

        vm.stopBroadcast();

        console2.log("Pool initialized and governance configured");
    }
}
