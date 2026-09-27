// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {VestingAccounting} from "../src/VestingAccounting.sol";
import {TestBase} from "./support/TestBase.sol";
import {ReferenceModel} from "./support/ReferenceModel.sol";

contract BeneficiaryContract {
    // Deliberately has no payable receive/fallback: a claim must not attempt payment.
    function claim(VestingAccounting vesting) external returns (uint256) {
        return vesting.claim();
    }
}

contract VestingAccountingTest is TestBase {
    address internal constant BENEFICIARY = address(0xBEEF);
    uint256 internal constant MAX = type(uint256).max;
    VestingAccounting internal vesting;

    event Claimed(address indexed beneficiary, uint256 amount, uint256 totalClaimed);

    function setUp() public {
        vesting = new VestingAccounting(BENEFICIARY, 101, 1000, 3, 7);
    }

    function testConstructorStoresImmutableSchedule() public view {
        assertEq(vesting.beneficiary(), BENEFICIARY);
        assertEq(vesting.grant(), 101);
        assertEq(vesting.start(), 1000);
        assertEq(vesting.cliff(), 3);
        assertEq(vesting.duration(), 7);
        assertEq(vesting.end(), 1007);
        assertEq(vesting.claimed(), 0);
    }

    function testRejectsZeroBeneficiary() public {
        vm.expectRevert(VestingAccounting.InvalidBeneficiary.selector);
        new VestingAccounting(address(0), 1, 0, 0, 1);
    }

    function testRejectsZeroDuration() public {
        vm.expectRevert(VestingAccounting.ZeroDuration.selector);
        new VestingAccounting(BENEFICIARY, 1, 0, 0, 0);
    }

    function testRejectsCliffBeyondDuration() public {
        vm.expectRevert(VestingAccounting.CliffBeyondDuration.selector);
        new VestingAccounting(BENEFICIARY, 1, 0, 8, 7);
    }

    function testRejectsEndAndCliffTimestampOverflow() public {
        vm.expectRevert(VestingAccounting.TimestampOverflow.selector);
        new VestingAccounting(BENEFICIARY, 1, MAX, 0, 1);
        vm.expectRevert(VestingAccounting.TimestampOverflow.selector);
        new VestingAccounting(BENEFICIARY, 1, 1, MAX, MAX);
        vm.expectRevert(VestingAccounting.TimestampOverflow.selector);
        new VestingAccounting(BENEFICIARY, 1, MAX - 6, 0, 7);
    }

    function testExactBoundariesAndNonDivisibleDuration() public view {
        assertEq(vesting.vestedAt(0), 0);
        assertEq(vesting.vestedAt(999), 0);
        assertEq(vesting.vestedAt(1000), 0);
        assertEq(vesting.vestedAt(1002), 0);
        assertEq(vesting.vestedAt(1003), 43); // Catch-up from start at the cliff, not a new schedule.
        assertEq(vesting.vestedAt(1004), 57);
        assertEq(vesting.vestedAt(1006), 86);
        assertEq(vesting.vestedAt(1007), 101);
        assertEq(vesting.vestedAt(1008), 101);
        assertEq(vesting.vestedAt(MAX), 101);
    }

    function testZeroCliffStillLinearFromStart() public {
        VestingAccounting v = new VestingAccounting(BENEFICIARY, 10, 100, 0, 3);
        assertEq(v.vestedAt(99), 0);
        assertEq(v.vestedAt(100), 0);
        assertEq(v.vestedAt(101), 3);
        assertEq(v.vestedAt(102), 6);
        assertEq(v.vestedAt(103), 10);
    }

    function testCliffEqualDurationReleasesEverythingAtEnd() public {
        VestingAccounting v = new VestingAccounting(BENEFICIARY, MAX, 0, 7, 7);
        assertEq(v.vestedAt(6), 0);
        assertEq(v.vestedAt(7), MAX);
        vm.warp(7);
        vm.prank(BENEFICIARY);
        assertEq(v.claim(), MAX);
        vm.prank(BENEFICIARY);
        assertEq(v.claim(), 0);
    }

    function testTinyGrantsAgainstReferenceAtEverySecond() public {
        for (uint256 g; g <= 3; ++g) {
            VestingAccounting v = new VestingAccounting(BENEFICIARY, g, 100, 0, 11);
            uint256 total;
            for (uint256 t = 99; t <= 112; ++t) {
                uint256 expected = ReferenceModel.vested(g, 100, 0, 11, t);
                vm.warp(t);
                assertEq(v.vested(), expected);
                assertEq(v.claimable(), expected - total);
                vm.prank(BENEFICIARY);
                total += v.claim();
                assertEq(total, expected);
                assertEq(v.claimed(), total);
            }
            assertEq(total, g);
        }
    }

    function testOneUnitCannotBeClaimedUntilEnd() public {
        VestingAccounting v = new VestingAccounting(BENEFICIARY, 1, 0, 3, 11);
        assertEq(v.vestedAt(3), 0);
        assertEq(v.vestedAt(10), 0);
        assertEq(v.vestedAt(11), 1);
    }

    function testZeroGrantAllowsNoOpClaims() public {
        VestingAccounting v = new VestingAccounting(BENEFICIARY, 0, 0, 0, MAX);
        vm.warp(MAX);
        vm.prank(BENEFICIARY);
        assertEq(v.claim(), 0);
        assertEq(v.vested(), 0);
        assertEq(v.claimable(), 0);
        assertEq(v.claimed(), 0);
    }

    function testClaimEventAndRepeatedClaims() public {
        vm.warp(1002);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 0);
        vm.warp(1003);
        vm.expectEmit(true, false, false, true, address(vesting));
        emit Claimed(BENEFICIARY, 43, 43);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 43);
        assertEq(vesting.claimable(), 0);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 0);
        vm.warp(1004);
        vm.expectEmit(true, false, false, true, address(vesting));
        emit Claimed(BENEFICIARY, 14, 57);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 14);
        vm.warp(1007);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 44);
        vm.warp(MAX);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 0);
        assertEq(vesting.claimed(), 101);
    }

    function testUnauthorizedBeforeCliffAndAfterVesting() public {
        vm.warp(999);
        vm.expectRevert(VestingAccounting.Unauthorized.selector);
        vesting.claim(); // Even a zero claim is restricted, including the deployer.
        vm.warp(1007);
        vm.prank(address(0xCAFE));
        vm.expectRevert(VestingAccounting.Unauthorized.selector);
        vesting.claim();
        assertEq(vesting.claimed(), 0);
        assertEq(vesting.claimable(), 101);
    }

    function testBeneficiaryMayBeANonpayableContract() public {
        BeneficiaryContract beneficiary = new BeneficiaryContract();
        VestingAccounting v = new VestingAccounting(address(beneficiary), 5, 0, 0, 1);
        vm.warp(1);
        assertEq(beneficiary.claim(v), 5);
        assertEq(address(v).balance, 0);
        assertEq(address(beneficiary).balance, 0);
    }

    function testRejectsEtherAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(vesting).call{value: 1}("");
        assertTrue(!success);
        (success,) =
            address(vesting).call(abi.encodeWithSignature("transferOwnership(address)", address(this)));
        assertTrue(!success);
        (success,) = address(vesting).call{value: 1}(abi.encodeCall(vesting.claim, ()));
        assertTrue(!success);
        assertEq(address(vesting).balance, 0);
    }

    function testForcedBalanceDoesNotAffectAccounting() public {
        vm.deal(address(vesting), 3 ether); // Models an unsolicited balance without a payable call.
        vm.warp(1007);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 101);
        assertEq(address(vesting).balance, 3 ether);
    }

    function testBackwardTimeDoesNotUnderflowOrReduceClaims() public {
        vm.warp(1004);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 57);
        vm.warp(0);
        assertEq(vesting.claimable(), 0);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 0);
        assertEq(vesting.claimed(), 57);
        vm.warp(1007);
        vm.prank(BENEFICIARY);
        assertEq(vesting.claim(), 44);
    }

    function testMaximumGrantDurationAndTimestampAgainstReference() public {
        VestingAccounting v = new VestingAccounting(BENEFICIARY, MAX, 0, 0, MAX);
        uint256[7] memory times = [uint256(0), 1, 2, MAX / 2, MAX - 2, MAX - 1, MAX];
        for (uint256 i; i < times.length; ++i) {
            uint256 t = times[i];
            assertEq(v.vestedAt(t), t); // MAX * t / MAX = t, including 512-bit products.
            assertEq(v.vestedAt(t), ReferenceModel.vested(MAX, 0, 0, MAX, t));
        }
        vm.warp(MAX - 1);
        vm.prank(BENEFICIARY);
        assertEq(v.claim(), MAX - 1);
        vm.warp(MAX);
        vm.prank(BENEFICIARY);
        assertEq(v.claim(), 1);
        vm.prank(BENEFICIARY);
        assertEq(v.claim(), 0);
        assertEq(v.claimed(), MAX);
    }

    function testMaximumValidStartAndEnd() public {
        VestingAccounting v = new VestingAccounting(BENEFICIARY, MAX, MAX - 1, 0, 1);
        assertEq(v.vestedAt(MAX - 2), 0);
        assertEq(v.vestedAt(MAX - 1), 0);
        assertEq(v.vestedAt(MAX), MAX);
        v = new VestingAccounting(BENEFICIARY, MAX, MAX - 7, 3, 7);
        assertEq(v.vestedAt(MAX - 5), 0);
        assertEq(v.vestedAt(MAX - 4), ReferenceModel.vested(MAX, MAX - 7, 3, 7, MAX - 4));
        assertEq(v.vestedAt(MAX), MAX);
    }

    function testMaximumCliffAndPowerOfTwoDuration() public {
        VestingAccounting v = new VestingAccounting(BENEFICIARY, MAX, 0, MAX, MAX);
        assertEq(v.vestedAt(MAX - 1), 0);
        assertEq(v.vestedAt(MAX), MAX);
        v = new VestingAccounting(BENEFICIARY, MAX, 0, 0, uint256(1) << 255);
        uint256 elapsed = (uint256(1) << 255) - 1;
        assertEq(v.vestedAt(elapsed), MAX - 2);
        assertEq(v.vestedAt(elapsed), ReferenceModel.vested(MAX, 0, 0, uint256(1) << 255, elapsed));
    }

    function testFuzzReferenceMatchesSafeNativeArithmetic(
        uint128 grant,
        uint128 durationSeed,
        uint128 timeSeed
    ) public pure {
        uint256 duration = uint256(durationSeed) + 1;
        uint256 elapsed = uint256(timeSeed) % duration;
        assertEq(ReferenceModel.vested(grant, 0, 0, duration, elapsed), uint256(grant) * elapsed / duration);
    }

    function testFuzzFullWidthVestingAgainstReference(
        uint256 grant,
        uint256 startSeed,
        uint256 durationSeed,
        uint256 cliffSeed,
        uint256 timeSeed
    ) public {
        (uint256 start, uint256 cliff, uint256 duration) = _schedule(startSeed, durationSeed, cliffSeed);
        VestingAccounting v = new VestingAccounting(BENEFICIARY, grant, start, cliff, duration);
        _compare(v, timeSeed);
        _compare(v, start);
        _compare(v, start + cliff);
        if (start + cliff > 0) _compare(v, start + cliff - 1);
        _compare(v, start + duration - 1);
        _compare(v, start + duration);
        uint256 elapsed = timeSeed % duration;
        _compare(v, start + elapsed);
        uint256 before = v.vestedAt(start + elapsed);
        assertTrue(v.vestedAt(start + elapsed + 1) >= before);
    }

    function testFuzzRepeatedClaimsConserveGrant(
        uint256 grant,
        uint256 startSeed,
        uint256 durationSeed,
        uint256 cliffSeed,
        uint256 seed
    ) public {
        (uint256 start, uint256 cliff, uint256 duration) = _schedule(startSeed, durationSeed, cliffSeed);
        VestingAccounting v = new VestingAccounting(BENEFICIARY, grant, start, cliff, duration);
        uint256 elapsed;
        uint256 total;
        for (uint256 i; i < 12; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 remaining = duration - elapsed;
            if (remaining > 0) elapsed += seed % remaining;
            vm.warp(start + elapsed);
            uint256 expected = ReferenceModel.vested(grant, start, cliff, duration, start + elapsed);
            assertEq(v.claimable(), expected - total);
            vm.prank(BENEFICIARY);
            total += v.claim();
            assertEq(total, expected);
            assertEq(v.claimed(), total);
            assertTrue(total <= grant);
            vm.prank(BENEFICIARY);
            assertEq(v.claim(), 0);
            assertEq(v.claimable(), 0);
        }
        vm.warp(v.end());
        vm.prank(BENEFICIARY);
        total += v.claim();
        assertEq(total, grant);
        assertEq(v.claimed(), grant);
        vm.prank(BENEFICIARY);
        assertEq(v.claim(), 0);
    }

    function testFuzzUnauthorizedCaller(address caller, uint256 timestamp) public {
        if (caller == BENEFICIARY) return;
        vm.warp(timestamp);
        vm.prank(caller);
        vm.expectRevert(VestingAccounting.Unauthorized.selector);
        vesting.claim();
        assertEq(vesting.claimed(), 0);
    }

    function testFuzzRejectsAnyTimestampOverflow(uint256 startSeed, uint256 excessSeed) public {
        uint256 start = startSeed == 0 ? 1 : startSeed;
        uint256 duration = (MAX - start) + 1 + (excessSeed % start);
        vm.expectRevert(VestingAccounting.TimestampOverflow.selector);
        new VestingAccounting(BENEFICIARY, 1, start, 0, duration);
    }

    function testFuzzRejectsAnyCliffBeyondDuration(uint256 durationSeed, uint256 excessSeed) public {
        uint256 duration = (durationSeed % (MAX - 1)) + 1;
        uint256 cliff = duration + 1 + (excessSeed % (MAX - duration));
        vm.expectRevert(VestingAccounting.CliffBeyondDuration.selector);
        new VestingAccounting(BENEFICIARY, 1, 0, cliff, duration);
    }

    function _schedule(uint256 startSeed, uint256 durationSeed, uint256 cliffSeed)
        private
        pure
        returns (uint256 start, uint256 cliff, uint256 duration)
    {
        duration = durationSeed == 0 ? 1 : durationSeed;
        start = startSeed % (MAX - duration + 1);
        cliff = duration == MAX ? cliffSeed : cliffSeed % (duration + 1);
    }

    function _compare(VestingAccounting v, uint256 timestamp) private view {
        uint256 expected = ReferenceModel.vested(v.grant(), v.start(), v.cliff(), v.duration(), timestamp);
        assertEq(v.vestedAt(timestamp), expected);
        assertTrue(expected <= v.grant());
    }
}
