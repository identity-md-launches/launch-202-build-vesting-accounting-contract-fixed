// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {VestingAccounting} from "../src/VestingAccounting.sol";
import {DemoConfig} from "./DemoConfig.sol";

interface DeploymentVm {
    function envAddress(string calldata name) external view returns (address);
    function startBroadcast(address signer) external;
    function stopBroadcast() external;
}

contract DeploySepolia {
    error DeploymentDisabled();
    error WrongChain(uint256 actual);
    error InvalidDeployer();

    DeploymentVm private constant vm = DeploymentVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (VestingAccounting deployed) {
        _validateNetwork();
        address deployer = vm.envAddress("SEPOLIA_DEPLOYER");
        if (deployer == address(0)) revert InvalidDeployer();
        vm.startBroadcast(deployer);
        deployed = deployDemo();
        vm.stopBroadcast();
    }

    /// @dev Tests call exactly the deployment path used by run(), without environment mutation or broadcast.
    function deployDemo() public returns (VestingAccounting) {
        _validateNetwork();
        return new VestingAccounting(
            DemoConfig.BENEFICIARY, DemoConfig.GRANT, DemoConfig.START, DemoConfig.CLIFF, DemoConfig.DURATION
        );
    }

    function _validateNetwork() private view {
        if (!DemoConfig.DEPLOYMENT_ENABLED) revert DeploymentDisabled();
        if (block.chainid != DemoConfig.CHAIN_ID) revert WrongChain(block.chainid);
    }
}
