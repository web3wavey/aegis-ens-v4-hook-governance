// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPermissionedRegistry} from "@ensdomains/contracts-v2/registry/interfaces/IPermissionedRegistry.sol";

import {IOperatorRoleManager} from "./interfaces/IOperatorRoleManager.sol";

/// @title OperatorRoleManager
/// @notice Manages pool operators using ENSv2 identities.
///
/// The parent ENS domain remains ultimate authority.
///
/// Example:
///
/// project.eth
///     └── operator.project.eth
///             ├── alice.operator.project.eth
///             └── bob.operator.project.eth
///
/// ENS ownership and pool authorization are deliberately separate.
/// Operator identity names may remain controlled by the parent while
/// individual wallets are assigned to use those identities.

contract OperatorRoleManager is IOperatorRoleManager {
    IPermissionedRegistry public immutable governanceRegistry;

    struct GovernanceConfig {
        address operatorAdmin;
        address operatorAdminIdentityRegistry;
        uint256 operatorAdminIdentityResource;
        bool configured;
    }

    struct OperatorAssignment {
        address identityRegistry;
        uint256 identityResource;
        bool active;
    }

    mapping(uint256 => GovernanceConfig) public governanceConfigs;

    mapping(uint256 governanceResource => mapping(address account => OperatorAssignment)) internal _operators;

    error ZeroAddress();
    error InvalidIdentity();
    error GovernanceNotConfigured();
    error GovernanceAlreadyConfigured();
    error OnlyParentOwner();
    error OnlyGovernanceAdmin();
    error OperatorNotActive();

    event GovernanceConfigured(
        uint256 indexed governanceResource,
        address indexed parentOwner,
        address indexed operatorAdmin,
        address operatorAdminIdentityRegistry,
        uint256 operatorAdminIdentityResource
    );

    event OperatorAdminUpdated(
        uint256 indexed governanceResource,
        address indexed previousAdmin,
        address indexed newAdmin,
        address identityRegistry,
        uint256 identityResource
    );

    event OperatorAdminRevoked(uint256 indexed governanceResource, address indexed previousAdmin);

    event OperatorAdded(
        uint256 indexed governanceResource,
        address indexed operator,
        address indexed authorizedBy,
        address identityRegistry,
        uint256 identityResource
    );

    event OperatorRemoved(
        uint256 indexed governanceResource,
        address indexed operator,
        address indexed authorizedBy,
        address identityRegistry,
        uint256 identityResource
    );

    constructor(IPermissionedRegistry _governanceRegistry) {
        if (address(_governanceRegistry) == address(0)) {
            revert ZeroAddress();
        }

        governanceRegistry = _governanceRegistry;
    }

    /// @notice Configure an ENS governance resource.
    ///
    /// Only the CURRENT owner of ENS domain can perform this.
    function configureGovernance(
        uint256 governanceResource,
        address operatorAdmin,
        address operatorAdminIdentityRegistry,
        uint256 operatorAdminIdentityResource
    ) external {
        address currentParentOwner = governanceRegistry.getOwner(governanceResource);

        if (msg.sender != currentParentOwner) {
            revert OnlyParentOwner();
        }

        GovernanceConfig storage config = governanceConfigs[governanceResource];

        if (config.configured) {
            revert GovernanceAlreadyConfigured();
        }

        if (operatorAdmin == address(0)) {
            revert ZeroAddress();
        }

        _requireValidIdentity(operatorAdminIdentityRegistry, operatorAdminIdentityResource);

        config.operatorAdmin = operatorAdmin;
        config.operatorAdminIdentityRegistry = operatorAdminIdentityRegistry;
        config.operatorAdminIdentityResource = operatorAdminIdentityResource;
        config.configured = true;

        emit GovernanceConfigured(
            governanceResource,
            currentParentOwner,
            operatorAdmin,
            operatorAdminIdentityRegistry,
            operatorAdminIdentityResource
        );
    }

    /// @notice Parent project.eth owner can replace operator.project.eth's
    /// active controller.
    function setOperatorAdmin(
        uint256 governanceResource,
        address newAdmin,
        address identityRegistry,
        uint256 identityResource
    ) external {
        _requireParentOwner(governanceResource);

        GovernanceConfig storage config = governanceConfigs[governanceResource];

        if (!config.configured) {
            revert GovernanceNotConfigured();
        }

        if (newAdmin == address(0)) {
            revert ZeroAddress();
        }

        _requireValidIdentity(identityRegistry, identityResource);

        address previousAdmin = config.operatorAdmin;

        config.operatorAdmin = newAdmin;
        config.operatorAdminIdentityRegistry = identityRegistry;
        config.operatorAdminIdentityResource = identityResource;

        emit OperatorAdminUpdated(governanceResource, previousAdmin, newAdmin, identityRegistry, identityResource);
    }

    /// @notice Parent can completely disable the delegated operator admin.
    function revokeOperatorAdmin(uint256 governanceResource) external {
        _requireParentOwner(governanceResource);

        GovernanceConfig storage config = governanceConfigs[governanceResource];

        if (!config.configured) {
            revert GovernanceNotConfigured();
        }

        address previousAdmin = config.operatorAdmin;

        config.operatorAdmin = address(0);
        config.operatorAdminIdentityRegistry = address(0);
        config.operatorAdminIdentityResource = 0;

        emit OperatorAdminRevoked(governanceResource, previousAdmin);
    }

    /// @notice Add or reactivate a pool operator.
    ///
    /// Callable only by:
    /// - current project.eth owner, OR
    /// - designated operator.project.eth administrator.
    function addOperator(
        uint256 governanceResource,
        address account,
        address identityRegistry,
        uint256 identityResource
    ) external {
        _requireGovernanceAdmin(governanceResource);

        if (account == address(0)) {
            revert ZeroAddress();
        }

        _requireValidIdentity(identityRegistry, identityResource);

        _operators[governanceResource][account] =
            OperatorAssignment({identityRegistry: identityRegistry, identityResource: identityResource, active: true});

        emit OperatorAdded(governanceResource, account, msg.sender, identityRegistry, identityResource);
    }

    /// @notice Revoke pool authority from an operator.
    function removeOperator(uint256 governanceResource, address account) external {
        _requireGovernanceAdmin(governanceResource);

        OperatorAssignment storage assignment = _operators[governanceResource][account];

        if (!assignment.active) {
            revert OperatorNotActive();
        }

        assignment.active = false;

        emit OperatorRemoved(
            governanceResource, account, msg.sender, assignment.identityRegistry, assignment.identityResource
        );
    }

    function isOperator(uint256 governanceResource, address account) external view returns (bool) {
        return _operators[governanceResource][account].active;
    }

    function operatorIdentity(uint256 governanceResource, address account)
        external
        view
        returns (address identityRegistry, uint256 identityResource, bool active)
    {
        OperatorAssignment memory assignment = _operators[governanceResource][account];

        return (assignment.identityRegistry, assignment.identityResource, assignment.active);
    }

    /// @notice Current ultimate authority follows ownership of project.eth.
    function parentOwner(uint256 governanceResource) external view returns (address) {
        return governanceRegistry.getOwner(governanceResource);
    }

    function _requireParentOwner(uint256 governanceResource) internal view {
        if (msg.sender != governanceRegistry.getOwner(governanceResource)) {
            revert OnlyParentOwner();
        }
    }

    function _requireGovernanceAdmin(uint256 governanceResource) internal view {
        GovernanceConfig memory config = governanceConfigs[governanceResource];

        if (!config.configured) {
            revert GovernanceNotConfigured();
        }

        address parent = governanceRegistry.getOwner(governanceResource);

        if (msg.sender != parent && msg.sender != config.operatorAdmin) {
            revert OnlyGovernanceAdmin();
        }
    }

    function _requireValidIdentity(address identityRegistry, uint256 identityResource) internal view {
        if (identityRegistry == address(0) || identityResource == 0) {
            revert InvalidIdentity();
        }

        address identityOwner = IPermissionedRegistry(identityRegistry).getOwner(identityResource);

        if (identityOwner == address(0)) {
            revert InvalidIdentity();
        }
    }
}
