// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// The small cheatcode interface needed by these tests; no downloaded test framework.
interface Vm {
    function warp(uint256 timestamp) external;
    function prank(address sender) external;
    function deal(address account, uint256 balance) external;
    function expectRevert(bytes4 selector) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function chainId(uint256 chainId_) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "uint mismatch");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "address mismatch");
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "assertion failed");
    }
}
