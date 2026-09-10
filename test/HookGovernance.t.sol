// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {HookGovernance} from "../src/HookGovernance.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";

import {HookMiner} from "v4-periphery/test/shared/HookMiner.sol";

import {IPermissionedRegistry} from "@ensdomains/contracts-v2/registry/interfaces/IPermissionedRegistry.sol";

// =============================================================
//                    MOCK ENSV2 REGISTRY
// =============================================================

contract MockPermissionedRegistry {
    mapping(uint256 => mapping(address => uint256)) internal _roles;

    function setRole(uint256 resource, address account, uint256 roleBitmap) external {
        _roles[resource][account] = roleBitmap;
    }

    function grantRole(uint256 resource, address account, uint256 roleBitmap) external {
        _roles[resource][account] |= roleBitmap;
    }

    function revokeRole(uint256 resource, address account, uint256 roleBitmap) external {
        _roles[resource][account] &= ~roleBitmap;
    }

    function hasRoles(uint256 resource, uint256 roleBitmap, address account) external view returns (bool) {
        return (_roles[resource][account] & roleBitmap) == roleBitmap;
    }
}

// =============================================================
//                       TEST CONTRACT
// =============================================================

contract HookGovernanceTest is Test {
    using PoolIdLibrary for PoolKey;

    HookGovernance internal hook;
    MockPermissionedRegistry internal ens;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint256 internal constant RESOURCE_A = 1;
    uint256 internal constant RESOURCE_B = 2;

    PoolId internal poolA;
    PoolId internal poolB;

    function setUp() public {
        ens = new MockPermissionedRegistry();

        address mockPoolManager = address(0x1234);

        uint160 mask = uint160(Hooks.ALL_HOOK_MASK);

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG) | uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG)
            | uint160(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG);

        bytes memory constructorArgs =
            abi.encode(IPoolManager(mockPoolManager), IPermissionedRegistry(address(ens)), address(this));

        (, bytes32 salt) = HookMiner.find(address(this), flags, type(HookGovernance).creationCode, constructorArgs);

        hook = new HookGovernance{salt: salt}(
            IPoolManager(mockPoolManager), IPermissionedRegistry(address(ens)), address(this)
        );

        assertEq(uint160(address(hook)) & mask, flags);

        poolA = _poolKeyA().toId();
        poolB = _poolKeyB().toId();

        hook.configurePool(poolA, RESOURCE_A);
        hook.configurePool(poolB, RESOURCE_B);

        ens.setRole(RESOURCE_A, alice, hook.ROLE_OPERATOR());
    }

    // =============================================================
    //                       SETUP TESTS
    // =============================================================

    function test_hookHasRequiredPermissions() public {
        uint160 mask = uint160(Hooks.ALL_HOOK_MASK);

        uint160 expectedFlags = uint160(Hooks.BEFORE_SWAP_FLAG) | uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG)
            | uint160(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG);

        assertEq(uint160(address(hook)) & mask, expectedFlags);
    }

    function test_poolAConfiguredWithResourceA() public view {
        assertEq(hook.ensResourceForPool(poolA), RESOURCE_A);
    }

    function test_poolBConfiguredWithResourceB() public view {
        assertEq(hook.ensResourceForPool(poolB), RESOURCE_B);
    }

    // =============================================================
    //                       AUTHORIZATION
    // =============================================================

    function test_aliceIsOperatorForPoolA() public view {
        assertTrue(hook.isOperator(poolA, alice));
    }

    function test_aliceIsNotOperatorForPoolB() public view {
        assertFalse(hook.isOperator(poolB, alice));
    }

    function test_bobIsNotOperatorForPoolA() public view {
        assertFalse(hook.isOperator(poolA, bob));
    }

    // =============================================================
    //                         PAUSING
    // =============================================================

    function test_aliceCanPausePoolA() public {
        vm.prank(alice);

        hook.pausePool(poolA);

        assertTrue(hook.isPaused(poolA));
    }

    function test_aliceCannotPausePoolB() public {
        vm.prank(alice);

        vm.expectRevert(HookGovernance.Unauthorized.selector);

        hook.pausePool(poolB);
    }

    function test_bobCannotPausePoolA() public {
        vm.prank(bob);

        vm.expectRevert(HookGovernance.Unauthorized.selector);

        hook.pausePool(poolA);
    }

    function test_unconfiguredPoolCannotBePaused() public {
        PoolId unknownPool = PoolId.wrap(bytes32(uint256(999)));

        vm.prank(alice);

        vm.expectRevert(HookGovernance.PoolNotConfigured.selector);

        hook.pausePool(unknownPool);
    }

    // =============================================================
    //                         UNPAUSING
    // =============================================================

    function test_aliceCanUnpausePoolA() public {
        vm.prank(alice);
        hook.pausePool(poolA);

        assertTrue(hook.isPaused(poolA));

        vm.prank(alice);
        hook.unpausePool(poolA);

        assertFalse(hook.isPaused(poolA));
    }

    function test_bobCannotUnpausePoolA() public {
        vm.prank(alice);
        hook.pausePool(poolA);

        vm.prank(bob);

        vm.expectRevert(HookGovernance.Unauthorized.selector);

        hook.unpausePool(poolA);
    }

    // =============================================================
    //                       POOL ISOLATION
    // =============================================================

    function test_poolPermissionsAreIsolated() public {
        // Alice can control Pool A.
        vm.prank(alice);
        hook.pausePool(poolA);

        assertTrue(hook.isPaused(poolA));
        assertFalse(hook.isPaused(poolB));

        // Alice cannot control Pool B.
        vm.prank(alice);

        vm.expectRevert(HookGovernance.Unauthorized.selector);

        hook.pausePool(poolB);

        // Pool B remains unaffected.
        assertFalse(hook.isPaused(poolB));
    }

    // =============================================================
    //                       BEFORE SWAP
    // =============================================================

    function test_beforeSwapRevertsWhenPoolIsPaused() public {
        vm.prank(alice);
        hook.pausePool(poolA);

        PoolKey memory key = _poolKeyA();

        vm.prank(address(0x1234));

        vm.expectRevert(HookGovernance.PoolIsPaused.selector);

        hook.beforeSwap(
            address(this),
            key,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1, sqrtPriceLimitX96: 1}),
            ""
        );
    }

    function test_beforeAddLiquidityRevertsWhenPoolIsPaused() public {
        vm.prank(alice);
        hook.pausePool(poolA);

        PoolKey memory key = _poolKeyA();

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: -60, tickUpper: 60, liquidityDelta: 1 ether, salt: bytes32(0)
        });

        vm.prank(address(0x1234));
        vm.expectRevert(HookGovernance.PoolIsPaused.selector);

        hook.beforeAddLiquidity(address(this), key, params, "");
    }

    function test_beforeRemoveLiquidityRevertsWhenPoolIsPaused() public {
        vm.prank(alice);
        hook.pausePool(poolA);

        PoolKey memory key = _poolKeyA();

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: -60, tickUpper: 60, liquidityDelta: -1 ether, salt: bytes32(0)
        });

        vm.prank(address(0x1234));
        vm.expectRevert(HookGovernance.PoolIsPaused.selector);

        hook.beforeRemoveLiquidity(address(this), key, params, "");
    }

    function test_beforeSwapSucceedsWhenPoolIsUnpaused() public {
        PoolKey memory key = _poolKeyA();

        vm.prank(address(0x1234));

        (bytes4 selector,, uint24 fee) = hook.beforeSwap(
            address(this),
            key,
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1, sqrtPriceLimitX96: 1}),
            ""
        );

        assertEq(selector, IHooks.beforeSwap.selector);

        assertEq(fee, 0);
    }

    function test_operatorCanBeTransferredWithoutRedeployment() public {
        // Alice initially controls Pool A.
        assertTrue(hook.isOperator(poolA, alice));
        assertFalse(hook.isOperator(poolA, bob));

        // Record the deployed hook and pool identity.
        address hookAddress = address(hook);
        PoolId originalPool = poolA;

        // Alice pauses the pool.
        vm.prank(alice);
        hook.pausePool(poolA);

        assertTrue(hook.isPaused(poolA));

        // Revoke Alice's ENSv2 capability.
        ens.revokeRole(RESOURCE_A, alice, hook.ROLE_OPERATOR());

        // Grant Bob the same ENSv2 capability.
        ens.grantRole(RESOURCE_A, bob, hook.ROLE_OPERATOR());

        // Verify the governance authority moved.
        assertFalse(hook.isOperator(poolA, alice));
        assertTrue(hook.isOperator(poolA, bob));

        // Alice can no longer govern the pool.
        vm.prank(alice);
        vm.expectRevert(HookGovernance.Unauthorized.selector);
        hook.unpausePool(poolA);

        // Bob can now govern the same pool.
        vm.prank(bob);
        hook.unpausePool(poolA);

        assertFalse(hook.isPaused(poolA));

        // The hook and pool identity never changed.
        assertEq(address(hook), hookAddress);
        assertEq(PoolId.unwrap(poolA), PoolId.unwrap(originalPool));
    }

    function test_onlyConfiguratorCanConfigurePool() public {
        PoolId newPool = PoolId.wrap(bytes32(uint256(12345)));

        vm.prank(alice);
        vm.expectRevert(HookGovernance.OnlyPoolConfigurator.selector);

        hook.configurePool(newPool, uint256(123));
    }

    // =============================================================
    //                         HELPERS
    // =============================================================

    function _poolKeyA() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }

    function _poolKeyB() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0x3000)),
            currency1: Currency.wrap(address(0x4000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
    }
}
