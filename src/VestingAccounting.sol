// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FullMath} from "./math/FullMath.sol";

/// @notice Immutable vesting of abstract units. Claims are accounting entries, never payments.
contract VestingAccounting {
    error InvalidBeneficiary();
    error ZeroDuration();
    error CliffBeyondDuration();
    error TimestampOverflow();
    error Unauthorized();

    event Claimed(address indexed beneficiary, uint256 amount, uint256 totalClaimed);

    address public immutable beneficiary;
    uint256 public immutable grant;
    uint256 public immutable start;
    /// @notice Offset in seconds from start, not an absolute timestamp.
    uint256 public immutable cliff;
    uint256 public immutable duration;
    uint256 public immutable end;
    uint256 public claimed;

    constructor(address beneficiary_, uint256 grant_, uint256 start_, uint256 cliff_, uint256 duration_) {
        if (beneficiary_ == address(0)) revert InvalidBeneficiary();
        if (duration_ == 0) revert ZeroDuration();
        if (cliff_ > duration_) revert CliffBeyondDuration();
        // Because cliff <= duration, this also proves start + cliff cannot overflow.
        if (start_ > type(uint256).max - duration_) revert TimestampOverflow();

        beneficiary = beneficiary_;
        grant = grant_;
        start = start_;
        cliff = cliff_;
        duration = duration_;
        end = start_ + duration_;
    }

    /// @notice Zero before the cliff; floor(grant * elapsed / duration) thereafter; grant at the end.
    /// @dev Full precision prevents overflow of the intermediate product, even for a maximum grant.
    function vestedAt(uint256 timestamp) public view returns (uint256) {
        if (timestamp < start + cliff) return 0;
        if (timestamp >= end) return grant;
        return FullMath.mulDiv(grant, timestamp - start, duration);
    }

    function vested() public view returns (uint256) {
        return vestedAt(block.timestamp);
    }

    /// @notice Currently vested units not already claimed.
    /// @dev Saturation also makes reads safe if a test or a chain reorganization moves time backwards.
    function claimable() public view returns (uint256) {
        uint256 available = vested();
        return available > claimed ? available - claimed : 0;
    }

    /// @notice Record all currently claimable units; a zero claim is a successful no-op with no event.
    function claim() external returns (uint256 amount) {
        if (msg.sender != beneficiary) revert Unauthorized();
        amount = claimable();
        if (amount != 0) {
            claimed += amount;
            emit Claimed(beneficiary, amount, claimed);
        }
    }
}
