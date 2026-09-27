// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DeploySepolia} from "../script/DeploySepolia.s.sol";
import {DemoConfig} from "../script/DemoConfig.sol";
import {VestingAccounting} from "../src/VestingAccounting.sol";
import {TestBase} from "./support/TestBase.sol";
import {ReferenceModel} from "./support/ReferenceModel.sol";

contract DeploymentTest is TestBase {
    function testDemoDeploymentEnabledAndUsesDocumentedArguments() public {
        assertTrue(DemoConfig.DEPLOYMENT_ENABLED);
        vm.chainId(11155111);
        VestingAccounting v = new DeploySepolia().deployDemo();
        assertEq(v.beneficiary(), 0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
        assertEq(v.grant(), 1_000_003);
        assertEq(v.start(), 1_800_000_000);
        assertEq(v.cliff(), 604_800);
        assertEq(v.duration(), 2_592_000);
        assertEq(v.end(), 1_802_592_000);
        vm.warp(v.start() + v.cliff());
        uint256 expected =
            ReferenceModel.vested(v.grant(), v.start(), v.cliff(), v.duration(), block.timestamp);
        assertEq(v.vested(), expected);
        vm.prank(v.beneficiary());
        assertEq(v.claim(), expected);
        vm.warp(v.end());
        vm.prank(v.beneficiary());
        assertEq(v.claim(), v.grant() - expected);
    }

    function testMainnetDeploymentRejected() public {
        DeploySepolia script = new DeploySepolia();
        vm.chainId(1);
        // Custom errors with arguments require the complete revert payload.
        (bool success, bytes memory reason) =
            address(script).call(abi.encodeCall(DeploySepolia.deployDemo, ()));
        assertTrue(!success);
        assertTrue(
            keccak256(reason) == keccak256(abi.encodeWithSelector(DeploySepolia.WrongChain.selector, 1))
        );
    }

    function testRunRejectsWrongChainBeforeReadingEnvironment() public {
        DeploySepolia script = new DeploySepolia();
        vm.chainId(31337);
        (bool success, bytes memory reason) = address(script).call(abi.encodeCall(DeploySepolia.run, ()));
        assertTrue(!success);
        assertTrue(
            keccak256(reason) == keccak256(abi.encodeWithSelector(DeploySepolia.WrongChain.selector, 31337))
        );
    }

    function testRuntimeDeploymentBaseline() public {
        vm.chainId(11155111);
        VestingAccounting v = new DeploySepolia().deployDemo();
        bytes memory runtime = address(v).code;
        assertTrue(runtime.length > 0 && runtime.length <= 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
            }
        }
        assertEq(v.claimed(), 0);
        assertEq(address(v).balance, 0);
    }
}
