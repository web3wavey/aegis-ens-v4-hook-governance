// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOperatorRoleManager {
    function isOperator(uint256 governanceResource, address account) external view returns (bool);

    function operatorIdentity(uint256 governanceResource, address account)
        external
        view
        returns (address identityRegistry, uint256 identityResource, bool active);
}
