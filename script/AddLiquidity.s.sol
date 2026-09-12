// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";

import {Actions} from "v4-periphery/src/libraries/Actions.sol";

import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";

contract AddLiquidity is Script {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_SPACING = 60;

    int24 internal constant TICK_LOWER = -887220;
    int24 internal constant TICK_UPPER = 887220;

    uint256 internal constant ETH_BUDGET = 0.01 ether;
    uint256 internal constant USDC_BUDGET = 30_000_000;

    struct LiquidityPlan {
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
    }

    function run() external returns (uint256 tokenId) {
        IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));

        IPositionManager positionManager = IPositionManager(vm.envAddress("POSITION_MANAGER"));

        address owner = vm.envAddress("POOL_CONFIGURATOR");

        PoolKey memory key = _buildPoolKey(vm.envAddress("MOCK_USDC"), vm.envAddress("HOOK"));

        PoolId poolId = key.toId();

        LiquidityPlan memory plan = _buildLiquidityPlan(manager, poolId);

        require(plan.amount0 <= ETH_BUDGET, "ETH budget exceeded");

        require(plan.amount1 <= USDC_BUDGET, "USDC budget exceeded");

        tokenId = positionManager.nextTokenId();

        console2.log("Pool ID:");
        console2.logBytes32(PoolId.unwrap(poolId));

        console2.log("LP token ID:", tokenId);

        console2.log("Liquidity:", plan.liquidity);

        console2.log("ETH required:", plan.amount0);

        console2.log("USDC required:", plan.amount1);

        bytes memory unlockData = _buildUnlockData(key, plan, owner);

        vm.startBroadcast();

        positionManager.modifyLiquidities{value: plan.amount0}(unlockData, block.timestamp + 10 minutes);

        vm.stopBroadcast();

        console2.log("Liquidity position minted successfully");
    }

    function _buildPoolKey(address mockUsdc, address hook) internal pure returns (PoolKey memory key) {
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(mockUsdc),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(hook)
        });
    }

    function _buildLiquidityPlan(IPoolManager manager, PoolId poolId)
        internal
        view
        returns (LiquidityPlan memory plan)
    {
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(TICK_LOWER);

        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(TICK_UPPER);

        plan.liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, ETH_BUDGET, USDC_BUDGET);

        plan.amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpper, plan.liquidity, true);

        plan.amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPriceX96, plan.liquidity, true);
    }

    function _buildUnlockData(PoolKey memory key, LiquidityPlan memory plan, address owner)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            key,
            TICK_LOWER,
            TICK_UPPER,
            uint256(plan.liquidity),
            uint128(plan.amount0),
            uint128(plan.amount1),
            owner,
            bytes("")
        );

        params[1] = abi.encode(key.currency0, key.currency1);

        return abi.encode(actions, params);
    }
}
