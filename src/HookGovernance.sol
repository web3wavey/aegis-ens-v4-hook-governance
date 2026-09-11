// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {IOperatorRoleManager} from "./interfaces/IOperatorRoleManager.sol";

/// @title HookGovernance
/// @notice ENSv2-powered governance and permissions for multiple Uniswap v4 pools.
///
/// One HookGovernance contract can serve multiple Uniswap v4 pools.
/// Each PoolId is mapped to its own ENSv2 resource.
///
/// ENSv2 is the source of truth for operator permissions.

contract HookGovernance is IHooks {
    using PoolIdLibrary for PoolKey;

    // =============================================================
    //                           STATE
    // =============================================================

    IPoolManager public immutable poolManager;
    IOperatorRoleManager public immutable operatorRoleManager;
    address public immutable poolConfigurator;

    struct PoolConfig {
        /// @notice ENSv2 resource governing this pool.
        uint256 ensResource;

        /// @notice Whether swaps are currently paused.
        bool paused;

        /// @notice Whether this pool has been configured.
        bool configured;
    }

    /// @notice Pool-specific governance configuration.

    mapping(PoolId => PoolConfig) public poolConfigs;

    // =============================================================
    //                            ERRORS
    // =============================================================

    error Unauthorized();
    error PoolNotConfigured();
    error PoolAlreadyConfigured();
    error OnlyPoolManager();
    error PoolIsPaused();
    error OnlyPoolConfigurator();
    error InvalidPoolConfigurator();
    error InvalidOperatorRoleManager();

    // =============================================================
    //                            EVENTS
    // =============================================================

    event PoolConfigured(PoolId indexed poolId, uint256 indexed ensResource);

    event PoolPaused(
        PoolId indexed poolId, address indexed operator, address indexed identityRegistry, uint256 identityResource
    );

    event PoolUnpaused(
        PoolId indexed poolId, address indexed operator, address indexed identityRegistry, uint256 identityResource
    );

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(IPoolManager _poolManager, IOperatorRoleManager _operatorRoleManager, address _poolConfigurator) {
        if (_poolConfigurator == address(0)) {
            revert InvalidPoolConfigurator();
        }
        if (address(_operatorRoleManager) == address(0)) {
            revert InvalidOperatorRoleManager();
        }

        if (_poolConfigurator == address(0)) {
            revert InvalidPoolConfigurator();
        }

        poolManager = _poolManager;
        operatorRoleManager = _operatorRoleManager;
        poolConfigurator = _poolConfigurator;

        Hooks.validateHookPermissions(
            IHooks(address(this)),
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: true,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
        );
    }

    // =============================================================
    //                     POOL CONFIGURATION
    // =============================================================

    /// @notice Associate a Uniswap v4 pool with an ENSv2 resource.
    ///
    /// This is unrestricted for the initial testing.
    /// Configuration will be restricted
    /// to ENSv2-controlled authority.

    function configurePool(PoolId poolId, uint256 ensResource) external onlyPoolConfigurator {
        PoolConfig storage config = poolConfigs[poolId];

        if (config.configured) {
            revert PoolAlreadyConfigured();
        }

        config.ensResource = ensResource;
        config.paused = false;
        config.configured = true;

        emit PoolConfigured(poolId, ensResource);
    }

    // =============================================================
    //                       AUTHORIZATION
    // =============================================================

    /// @notice Check whether an account is an operator for a pool.

    function isOperator(PoolId poolId, address account) public view returns (bool) {
        PoolConfig memory config = poolConfigs[poolId];

        if (!config.configured) {
            return false;
        }

        return operatorRoleManager.isOperator(config.ensResource, account);
    }

    /// @notice Require msg.sender to be an operator for a pool.
    function _requireOperator(PoolId poolId, address account)
        internal
        view
        returns (address identityRegistry, uint256 identityResource)
    {
        PoolConfig memory config = poolConfigs[poolId];

        if (!config.configured) {
            revert PoolNotConfigured();
        }

        bool active;

        (identityRegistry, identityResource, active) = operatorRoleManager.operatorIdentity(config.ensResource, account);

        if (!active) {
            revert Unauthorized();
        }
    }

    // =============================================================
    //                         PAUSE CONTROL
    // =============================================================

    /// @notice Pause swaps for a specific pool.
    ///
    /// Only an ENSv2 operator for that pool can pause it.

    function pausePool(PoolId poolId) external {
        PoolConfig storage config = poolConfigs[poolId];

        if (!config.configured) {
            revert PoolNotConfigured();
        }

        (address identityRegistry, uint256 identityResource) = _requireOperator(poolId, msg.sender);

        config.paused = true;

        emit PoolPaused(poolId, msg.sender, identityRegistry, identityResource);
    }

    /// @notice Unpause swaps for a specific pool.
    ///
    /// Only an ENSv2 operator for that pool can unpause it.

    function unpausePool(PoolId poolId) external {
        PoolConfig storage config = poolConfigs[poolId];

        if (!config.configured) {
            revert PoolNotConfigured();
        }

        (address identityRegistry, uint256 identityResource) = _requireOperator(poolId, msg.sender);

        config.paused = false;

        emit PoolUnpaused(poolId, msg.sender, identityRegistry, identityResource);
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /// @notice Return whether a pool is currently paused.

    function isPaused(PoolId poolId) public view returns (bool) {
        return poolConfigs[poolId].paused;
    }

    /// @notice Return the ENSv2 resource governing a pool.

    function ensResourceForPool(PoolId poolId) external view returns (uint256) {
        return poolConfigs[poolId].ensResource;
    }

    // =============================================================
    //                     INTERNAL MODIFIERS
    // =============================================================

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) {
            revert OnlyPoolManager();
        }
        _;
    }

    modifier onlyPoolConfigurator() {
        if (msg.sender != poolConfigurator) {
            revert OnlyPoolConfigurator();
        }
        _;
    }

    // =============================================================
    //                       BEFORE SWAP
    // =============================================================

    /// @notice Called by Uniswap v4 before a swap.
    ///
    /// The PoolKey identifies the pool, which is mapped to an
    /// ENSv2 resource through poolConfigs.
    ///
    /// If the pool is paused, every swap reverts.

    function beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        PoolConfig memory config = poolConfigs[poolId];

        if (!config.configured) {
            revert PoolNotConfigured();
        }

        if (config.paused) {
            revert PoolIsPaused();
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // =============================================================
    //                  UNUSED HOOK CALLBACKS
    // =============================================================
    //
    // These callbacks are required because IHooks defines the
    // complete Uniswap v4 hook interface.
    // =============================================================

    function beforeInitialize(address, PoolKey calldata, uint160) external onlyPoolManager returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external onlyPoolManager returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        PoolId poolId = key.toId();
        PoolConfig memory config = poolConfigs[poolId];

        if (!config.configured) {
            revert PoolNotConfigured();
        }

        if (config.paused) {
            revert PoolIsPaused();
        }

        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4) {
        PoolId poolId = key.toId();
        PoolConfig memory config = poolConfigs[poolId];

        if (!config.configured) {
            revert PoolNotConfigured();
        }

        if (config.paused) {
            revert PoolIsPaused();
        }
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }
}
