// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {OperatorRoleManager} from "../src/OperatorRoleManager.sol";

import {IPermissionedRegistry} from "@ensdomains/contracts-v2/registry/interfaces/IPermissionedRegistry.sol";

contract MockIdentityRegistry {
    mapping(uint256 => address) internal _owners;

    function setOwner(uint256 resource, address owner) external {
        _owners[resource] = owner;
    }

    function getOwner(uint256 resource) external view returns (address) {
        return _owners[resource];
    }
}

contract OperatorRoleManagerTest is Test {
    OperatorRoleManager internal manager;

    MockIdentityRegistry internal governanceRegistry;
    MockIdentityRegistry internal identityRegistry;

    address internal parent;
    address internal operatorAdmin;
    address internal newOperatorAdmin;

    address internal alice;
    address internal bob;
    address internal charlie;

    uint256 internal constant PROJECT_RESOURCE = 1;

    uint256 internal constant OPERATOR_ADMIN_ID = 100;
    uint256 internal constant NEW_OPERATOR_ADMIN_ID = 101;

    uint256 internal constant ALICE_ID = 200;
    uint256 internal constant BOB_ID = 201;
    uint256 internal constant CHARLIE_ID = 202;

    function setUp() public {
        parent = makeAddr("parent");
        operatorAdmin = makeAddr("operatorAdmin");
        newOperatorAdmin = makeAddr("newOperatorAdmin");

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        governanceRegistry = new MockIdentityRegistry();

        identityRegistry = new MockIdentityRegistry();

        // project.eth is owned by the parent.
        governanceRegistry.setOwner(PROJECT_RESOURCE, parent);

        /*
         * Important:
         *
         * The ENS identity names remain owned by the parent.
         *
         * Alice/Bob/etc. USE these identities in the application,
         * but do not own the ENS tokens themselves.
         */
        identityRegistry.setOwner(OPERATOR_ADMIN_ID, parent);

        identityRegistry.setOwner(NEW_OPERATOR_ADMIN_ID, parent);

        identityRegistry.setOwner(ALICE_ID, parent);

        identityRegistry.setOwner(BOB_ID, parent);

        identityRegistry.setOwner(CHARLIE_ID, parent);

        manager = new OperatorRoleManager(IPermissionedRegistry(address(governanceRegistry)));

        vm.prank(parent);

        manager.configureGovernance(PROJECT_RESOURCE, operatorAdmin, address(identityRegistry), OPERATOR_ADMIN_ID);
    }

    // =============================================================
    // GOVERNANCE CONFIGURATION
    // =============================================================

    function test_governanceConfiguredCorrectly() public view {
        (address configuredAdmin, address adminIdentityRegistry, uint256 adminIdentityResource, bool configured) =
            manager.governanceConfigs(PROJECT_RESOURCE);

        assertEq(configuredAdmin, operatorAdmin);

        assertEq(adminIdentityRegistry, address(identityRegistry));

        assertEq(adminIdentityResource, OPERATOR_ADMIN_ID);

        assertTrue(configured);
    }

    function test_nonParentCannotConfigureGovernance() public {
        uint256 anotherResource = 999;

        governanceRegistry.setOwner(anotherResource, parent);

        vm.prank(alice);

        vm.expectRevert(OperatorRoleManager.OnlyParentOwner.selector);

        manager.configureGovernance(anotherResource, operatorAdmin, address(identityRegistry), OPERATOR_ADMIN_ID);
    }

    // =============================================================
    // MULTIPLE OPERATORS
    // =============================================================

    function test_operatorAdminCanAddAliceAndBob() public {
        vm.startPrank(operatorAdmin);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        manager.addOperator(PROJECT_RESOURCE, bob, address(identityRegistry), BOB_ID);

        vm.stopPrank();

        assertTrue(manager.isOperator(PROJECT_RESOURCE, alice));

        assertTrue(manager.isOperator(PROJECT_RESOURCE, bob));

        assertFalse(manager.isOperator(PROJECT_RESOURCE, charlie));
    }

    function test_charlieCanHaveIdentityButNotBeOperator() public view {
        // Charlie's ENS identity exists...
        assertEq(identityRegistry.getOwner(CHARLIE_ID), parent);

        // ...but Charlie has not been authorized.
        assertFalse(manager.isOperator(PROJECT_RESOURCE, charlie));
    }

    // =============================================================
    // OPERATORS CANNOT MANAGE OTHER OPERATORS
    // =============================================================

    function test_aliceCannotAddCharlie() public {
        vm.prank(operatorAdmin);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        assertTrue(manager.isOperator(PROJECT_RESOURCE, alice));

        vm.prank(alice);

        vm.expectRevert(OperatorRoleManager.OnlyGovernanceAdmin.selector);

        manager.addOperator(PROJECT_RESOURCE, charlie, address(identityRegistry), CHARLIE_ID);
    }

    function test_bobCannotRemoveAlice() public {
        vm.startPrank(operatorAdmin);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        manager.addOperator(PROJECT_RESOURCE, bob, address(identityRegistry), BOB_ID);

        vm.stopPrank();

        vm.prank(bob);

        vm.expectRevert(OperatorRoleManager.OnlyGovernanceAdmin.selector);

        manager.removeOperator(PROJECT_RESOURCE, alice);

        // Alice remains active.
        assertTrue(manager.isOperator(PROJECT_RESOURCE, alice));
    }

    // =============================================================
    // OPERATOR ADMIN
    // =============================================================

    function test_operatorAdminCanRemoveAlice() public {
        vm.prank(operatorAdmin);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        assertTrue(manager.isOperator(PROJECT_RESOURCE, alice));

        vm.prank(operatorAdmin);

        manager.removeOperator(PROJECT_RESOURCE, alice);

        assertFalse(manager.isOperator(PROJECT_RESOURCE, alice));
    }

    // =============================================================
    // PARENT ULTIMATE AUTHORITY
    // =============================================================

    function test_parentCanAddOperatorDirectly() public {
        vm.prank(parent);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        assertTrue(manager.isOperator(PROJECT_RESOURCE, alice));
    }

    function test_parentCanRemoveOperatorDirectly() public {
        vm.prank(operatorAdmin);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        vm.prank(parent);

        manager.removeOperator(PROJECT_RESOURCE, alice);

        assertFalse(manager.isOperator(PROJECT_RESOURCE, alice));
    }

    function test_parentCanReplaceOperatorAdmin() public {
        vm.prank(parent);

        manager.setOperatorAdmin(PROJECT_RESOURCE, newOperatorAdmin, address(identityRegistry), NEW_OPERATOR_ADMIN_ID);

        // Old admin should no longer work.
        vm.prank(operatorAdmin);

        vm.expectRevert(OperatorRoleManager.OnlyGovernanceAdmin.selector);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        // New admin should work.
        vm.prank(newOperatorAdmin);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        assertTrue(manager.isOperator(PROJECT_RESOURCE, alice));
    }

    function test_parentCanRevokeOperatorAdmin() public {
        vm.prank(parent);

        manager.revokeOperatorAdmin(PROJECT_RESOURCE);

        vm.prank(operatorAdmin);

        vm.expectRevert(OperatorRoleManager.OnlyGovernanceAdmin.selector);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        // Parent still retains ultimate control.
        vm.prank(parent);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        assertTrue(manager.isOperator(PROJECT_RESOURCE, alice));
    }

    // =============================================================
    // ENS IDENTITY
    // =============================================================

    function test_operatorIdentityIsStored() public {
        vm.prank(operatorAdmin);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        (address registry, uint256 resource, bool active) = manager.operatorIdentity(PROJECT_RESOURCE, alice);

        assertEq(registry, address(identityRegistry));

        assertEq(resource, ALICE_ID);

        assertTrue(active);
    }

    function test_removedOperatorKeepsIdentityForAudit() public {
        vm.prank(operatorAdmin);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        vm.prank(operatorAdmin);

        manager.removeOperator(PROJECT_RESOURCE, alice);

        (address registry, uint256 resource, bool active) = manager.operatorIdentity(PROJECT_RESOURCE, alice);

        // Historical identity remains available.
        assertEq(registry, address(identityRegistry));

        assertEq(resource, ALICE_ID);

        assertFalse(active);
    }

    function test_invalidIdentityCannotBeAdded() public {
        uint256 nonexistentIdentity = 99999;

        vm.prank(operatorAdmin);

        vm.expectRevert(OperatorRoleManager.InvalidIdentity.selector);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), nonexistentIdentity);
    }

    // =============================================================
    // ENS PARENT OWNERSHIP TRANSFER
    // =============================================================

    function test_parentAuthorityFollowsENSOwnership() public {
        address newParent = makeAddr("newParent");

        // Simulate project.eth changing ownership.
        governanceRegistry.setOwner(PROJECT_RESOURCE, newParent);

        // Previous owner immediately loses ultimate authority.
        vm.prank(parent);

        vm.expectRevert(OperatorRoleManager.OnlyGovernanceAdmin.selector);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        // New ENS owner gains ultimate authority automatically.
        vm.prank(newParent);

        manager.addOperator(PROJECT_RESOURCE, alice, address(identityRegistry), ALICE_ID);

        assertTrue(manager.isOperator(PROJECT_RESOURCE, alice));
    }
}
