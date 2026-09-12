// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Currency} from "v4-core/types/Currency.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";

interface IAegisSwapRouter {
    function swapExactEthForToken(PoolKey memory key, uint128 amountIn, uint160 sqrtPriceLimitX96)
        external
        payable
        returns (uint256 amountOut);
}

contract SwapEthForUsdc is Script {
    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_SPACING = 60;

    uint128 internal constant AMOUNT_IN = 0.0001 ether;

    function run() external {
        address router = vm.envAddress("AEGIS_SWAP_ROUTER");

        address hook = vm.envAddress("HOOK");

        address mockUsdc = vm.envAddress("MOCK_USDC");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(mockUsdc),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });

        uint160 priceLimit = TickMath.MIN_SQRT_PRICE + 1;

        console2.log("Swap input ETH:", AMOUNT_IN);

        vm.startBroadcast();

        uint256 amountOut = IAegisSwapRouter(router).swapExactEthForToken{value: AMOUNT_IN}(key, AMOUNT_IN, priceLimit);

        vm.stopBroadcast();

        console2.log("MockUSDC received:", amountOut);
    }
}
