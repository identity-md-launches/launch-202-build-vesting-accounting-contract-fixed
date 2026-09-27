// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @dev Public demo values only. No secret material and no configuration reads in tests.
library DemoConfig {
    bool internal constant DEPLOYMENT_ENABLED = true;
    uint256 internal constant CHAIN_ID = 11155111;
    // Public Anvil test account #1. It must never be treated as a secure production identity.
    address internal constant BENEFICIARY = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 internal constant GRANT = 1_000_003;
    uint256 internal constant START = 1_800_000_000;
    uint256 internal constant CLIFF = 604_800;
    uint256 internal constant DURATION = 2_592_000;
}
