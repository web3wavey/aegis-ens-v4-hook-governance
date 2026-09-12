// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {IUnlockCallback} from "v4-core/interfaces/callback/IUnlockCallback.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Currency} from "v4-core/types/Currency.sol";

import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract AegisSwapRouter is IUnlockCallback {
    IPoolManager public immutable manager;

    error OnlyPoolManager();
    error InvalidNativePool();
    error InvalidSwapDelta();
    error TooMuchInput();
    error RefundFailed();

    struct CallbackData {
        address recipient;
        PoolKey key;
        IPoolManager.SwapParams params;
        uint256 maxInput;
    }

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    receive() external payable {}

    function swapExactEthForToken(PoolKey memory key, uint128 amountIn, uint160 sqrtPriceLimitX96)
        external
        payable
        returns (uint256 amountOut)
    {
        if (Currency.unwrap(key.currency0) != address(0)) {
            revert InvalidNativePool();
        }

        require(msg.value == amountIn, "Incorrect ETH value");

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true, amountSpecified: -int256(uint256(amountIn)), sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        bytes memory result = manager.unlock(
            abi.encode(CallbackData({recipient: msg.sender, key: key, params: params, maxInput: amountIn}))
        );

        amountOut = abi.decode(result, (uint256));

        uint256 refund = address(this).balance;

        if (refund != 0) {
            (bool ok,) = payable(msg.sender).call{value: refund}("");

            if (!ok) {
                revert RefundFailed();
            }
        }
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(manager)) {
            revert OnlyPoolManager();
        }

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.swap(data.key, data.params, bytes(""));

        int128 delta0 = delta.amount0();

        int128 delta1 = delta.amount1();

        if (delta0 >= 0 || delta1 <= 0) {
            revert InvalidSwapDelta();
        }

        uint256 amountIn = uint256(-int256(delta0));

        uint256 amountOut = uint256(int256(delta1));

        if (amountIn > data.maxInput) {
            revert TooMuchInput();
        }

        manager.settle{value: amountIn}();

        manager.take(data.key.currency1, data.recipient, amountOut);

        return abi.encode(amountOut);
    }
}
