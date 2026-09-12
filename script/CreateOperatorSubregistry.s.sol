// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

interface IVerifiableFactory {
    function deployProxy(address implementation, uint256 salt, bytes calldata data) external returns (address proxy);
}

interface IUserRegistryG2 {
    struct Grant {
        address account;
        uint256 roleBitmap;
    }

    function initialize(Grant[] calldata grants) external;
}

interface IRegistryG2 {
    function getState(uint256 anyId)
        external
        view
        returns (uint8 status, uint64 expiry, address latestOwner, uint256 tokenId, uint256 resource);

    function getSubregistry(string calldata label) external view returns (address);

    function setSubregistry(uint256 anyId, address registry) external;
}

contract CreateOperatorSubregistry is Script {
    uint256 internal constant ALL_ROLES = 0x1111111111111111111111111111111111111111111111111111111111111111;

    function run() external returns (address operatorSubregistry) {
        address projectSubregistry = vm.envAddress("PROJECT_SUBREGISTRY");

        address owner = vm.envAddress("POOL_CONFIGURATOR");

        string memory operatorLabel = vm.envOr("OPERATOR_LABEL", string("operator"));

        uint256 operatorTokenId = _validateOperator(projectSubregistry, operatorLabel, owner);

        uint256 salt = _makeSalt(projectSubregistry, operatorLabel, owner);

        console2.log("Project subregistry:", projectSubregistry);

        console2.log("Operator token ID:", operatorTokenId);

        vm.startBroadcast();

        operatorSubregistry =
            _deployUserRegistry(vm.envAddress("RESOLVER_FACTORY"), vm.envAddress("USER_REGISTRY_IMPL"), owner, salt);

        IRegistryG2(projectSubregistry).setSubregistry(operatorTokenId, operatorSubregistry);

        vm.stopBroadcast();

        console2.log("OPERATOR_SUBREGISTRY:", operatorSubregistry);
    }

    function _validateOperator(address projectSubregistry, string memory operatorLabel, address expectedOwner)
        internal
        view
        returns (uint256 tokenId)
    {
        uint256 labelhash = uint256(keccak256(bytes(operatorLabel)));

        (uint8 status,, address latestOwner, uint256 currentTokenId,) =
            IRegistryG2(projectSubregistry).getState(labelhash);

        require(status == 2, "operator not registered");

        require(latestOwner == expectedOwner, "wrong operator owner");

        require(
            IRegistryG2(projectSubregistry).getSubregistry(operatorLabel) == address(0),
            "operator already has subregistry"
        );

        return currentTokenId;
    }

    function _makeSalt(address projectSubregistry, string memory operatorLabel, address owner)
        internal
        pure
        returns (uint256)
    {
        return uint256(
            keccak256(
                abi.encode("AEGIS_OPERATOR_SUBREGISTRY", projectSubregistry, keccak256(bytes(operatorLabel)), owner)
            )
        );
    }

    function _deployUserRegistry(address factory, address implementation, address owner, uint256 salt)
        internal
        returns (address)
    {
        IUserRegistryG2.Grant[] memory grants = new IUserRegistryG2.Grant[](1);

        grants[0] = IUserRegistryG2.Grant({account: owner, roleBitmap: ALL_ROLES});

        bytes memory initData = abi.encodeCall(IUserRegistryG2.initialize, (grants));

        return IVerifiableFactory(factory).deployProxy(implementation, salt, initData);
    }
}
