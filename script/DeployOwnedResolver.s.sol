// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

interface IVerifiableFactory {
    function deployProxy(address implementation, uint256 salt, bytes calldata data) external returns (address proxy);

    function verifyContract(address proxy) external view returns (address implementation);
}

interface IPermissionedResolverG2 {
    struct Grant {
        address account;
        uint256 roleBitmap;
    }

    function initialize(Grant[] calldata grants, bytes[] calldata calls) external;
}

contract DeployOwnedResolver is Script {
    function run() external returns (address resolver) {
        address owner = vm.envAddress("POOL_CONFIGURATOR");

        address factoryAddress = vm.envAddress("RESOLVER_FACTORY");

        address implementation = vm.envAddress("RESOLVER_IMPL");

        /*
         * g2 PermissionedResolver roles:
         *
         * SET_ADDRESS
         * SET_TEXT
         * SET_CONTENTHASH
         * SET_ABI
         * SET_INTERFACE
         * SET_NAME
         * SET_DATA
         * LINK
         * CAN_NAME
         * UPGRADE
         *
         * Plus corresponding admin roles.
         */
        uint256 regularRoles = (uint256(1) << 0) | (uint256(1) << 4) | (uint256(1) << 8) | (uint256(1) << 12)
            | (uint256(1) << 16) | (uint256(1) << 20) | (uint256(1) << 24) | (uint256(1) << 28) | (uint256(1) << 120)
            | (uint256(1) << 124);

        uint256 roleBitmap = regularRoles | (regularRoles << 128);

        IPermissionedResolverG2.Grant[] memory grants = new IPermissionedResolverG2.Grant[](1);

        grants[0] = IPermissionedResolverG2.Grant({account: owner, roleBitmap: roleBitmap});

        bytes[] memory calls = new bytes[](0);

        bytes memory initData = abi.encodeCall(IPermissionedResolverG2.initialize, (grants, calls));

        bytes32 ownedResolverId = keccak256(bytes("OwnedResolver"));

        uint256 salt = uint256(keccak256(abi.encode(ownedResolverId, owner, uint256(0))));

        vm.startBroadcast();

        resolver = IVerifiableFactory(factoryAddress).deployProxy(implementation, salt, initData);

        vm.stopBroadcast();

        console2.log("OWNER:", owner);

        console2.log("OWNED_RESOLVER:", resolver);

        console2.log("FACTORY_ATTESTS:", IVerifiableFactory(factoryAddress).verifyContract(resolver));
    }
}
