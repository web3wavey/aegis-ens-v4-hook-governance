// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

interface IVerifiableFactory {
    function deployProxy(address implementation, uint256 salt, bytes calldata data) external returns (address proxy);
}

interface IUserRegistry {
    struct Grant {
        address account;
        uint256 roleBitmap;
    }

    // ETHOnline 2026 g2 deployed UserRegistryImpl initializer.
    function initialize(Grant[] calldata grants) external;
}

interface IParentRegistry {
    function getTokenId(uint256 anyId) external view returns (uint256 tokenId);

    function setSubregistry(uint256 anyId, address registry) external;

    function getSubregistry(string calldata label) external view returns (address);
}

contract CreateProjectSubregistry is Script {
    // ENSv2 EnhancedAccessControl: bit 0 of every 4-bit role slot.
    uint256 internal constant ALL_ROLES = 0x1111111111111111111111111111111111111111111111111111111111111111;

    function run() external returns (address subregistry) {
        address ethRegistry = vm.envAddress("ETH_REGISTRY");
        address factory = vm.envAddress("RESOLVER_FACTORY");
        address userRegistryImpl = vm.envAddress("USER_REGISTRY_IMPL");
        address owner = vm.envAddress("POOL_CONFIGURATOR");
        uint256 ensResource = vm.envUint("ENS_RESOURCE");

        // Resolve the CURRENT token ID from the stable resource ID.
        uint256 ensTokenId = IParentRegistry(ethRegistry).getTokenId(ensResource);

        IUserRegistry.Grant[] memory grants = new IUserRegistry.Grant[](1);
        grants[0] = IUserRegistry.Grant({account: owner, roleBitmap: ALL_ROLES});

        bytes memory initData = abi.encodeWithSelector(IUserRegistry.initialize.selector, grants);

        // Deterministic salt for this project's subregistry.
        uint256 salt = uint256(keccak256(abi.encode("AEGIS_PROJECT_SUBREGISTRY_G2", ensResource, owner)));

        console2.log("ETH Registry:", ethRegistry);
        console2.log("Parent owner:", owner);
        console2.log("ENS resource:", ensResource);
        console2.log("Current ENS token ID:", ensTokenId);
        console2.log("UserRegistry implementation:", userRegistryImpl);
        console2.log("VerifiableFactory:", factory);
        console2.log("Initializer selector:");
        console2.logBytes4(IUserRegistry.initialize.selector);

        vm.startBroadcast();

        // Deploy and initialize the ETHOnline 2026 g2 UserRegistry proxy.
        subregistry = IVerifiableFactory(factory).deployProxy(userRegistryImpl, salt, initData);

        // Attach it below the registered .eth name.
        // g2 working flow does not use the old setParent(address,string) step.
        IParentRegistry(ethRegistry).setSubregistry(ensTokenId, subregistry);

        vm.stopBroadcast();

        console2.log("PROJECT_SUBREGISTRY:", subregistry);
    }
}
