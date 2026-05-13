// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { ClaudelanceCore } from "../src/ClaudelanceCore.sol";
import { IClaudelanceCore } from "../src/interfaces/IClaudelanceCore.sol";
import { MockCUSD } from "./helpers/MockCUSD.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract ClaudelanceCoreTest is Test {
    ClaudelanceCore internal core;
    MockCUSD internal cusd;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal relayer = makeAddr("relayer");
    address internal poster = makeAddr("poster");
    address internal w1 = makeAddr("w1");
    address internal w2 = makeAddr("w2");
    address internal w3 = makeAddr("w3");
    address internal stranger = makeAddr("stranger");

    uint96 internal constant AMOUNT = 5e18;
    uint96 internal constant STAKE = 0.25e18;
    uint8 internal constant MAX_SLOTS = 5;
    uint64 internal constant DEADLINE = 2 days;

    function setUp() public {
        cusd = new MockCUSD();
        core = new ClaudelanceCore(IERC20(address(cusd)), treasury, relayer, owner);

        cusd.mint(poster, 100e18);
        cusd.mint(w1, 10e18);
        cusd.mint(w2, 10e18);
        cusd.mint(w3, 10e18);

        vm.prank(poster);
        cusd.approve(address(core), type(uint256).max);
        vm.prank(w1);
        cusd.approve(address(core), type(uint256).max);
        vm.prank(w2);
        cusd.approve(address(core), type(uint256).max);
        vm.prank(w3);
        cusd.approve(address(core), type(uint256).max);
    }

    function _post() internal returns (uint256) {
        vm.prank(poster);
        return core.postBounty(
            0,
            "github.com/employer/repo",
            "github.com/employer/repo/issues/1",
            keccak256("hash"),
            AMOUNT,
            MAX_SLOTS,
            STAKE,
            DEADLINE,
            true
        );
    }

    function _claim(uint256 id, address w) internal {
        vm.prank(w);
        core.claimSlot(id);
    }

    function _submit(uint256 id, address w) internal {
        vm.prank(w);
        core.submitPR(id, "github.com/employer/repo/pull/2", bytes32(uint256(0xabc)), "{}");
    }

    function _attest(uint256 id, address w, bool ok) internal {
        vm.prank(relayer);
        core.attestCI(id, w, ok);
    }

    function test_PostBounty_TransfersDepositAndEmits() public {
        uint256 posterBalanceBefore = cusd.balanceOf(poster);
        uint256 id = _post();
        assertEq(id, 1);
        assertEq(cusd.balanceOf(poster), posterBalanceBefore - AMOUNT);
        assertEq(cusd.balanceOf(address(core)), AMOUNT);
        IClaudelanceCore.Bounty memory b = core.getBounty(id);
        assertEq(b.poster, poster);
        assertEq(b.amount, AMOUNT);
        assertEq(uint8(b.status), uint8(IClaudelanceCore.BountyStatus.Open));
        assertEq(core.bountyCountByType(0), 1);
        assertEq(core.totalBountyVolume(), AMOUNT);
        assertEq(core.uniquePosterCount(), 1);
    }

    function test_PostBounty_RevertsOnInsufficientAllowance() public {
        vm.prank(poster);
        cusd.approve(address(core), 0);
        vm.expectRevert();
        vm.prank(poster);
        core.postBounty(
            0, "github.com/x/y", "github.com/x/y/issues/1", bytes32(0), AMOUNT, MAX_SLOTS, STAKE, DEADLINE, true
        );
    }

    function test_PostBounty_RevertsOnInvalidParams() public {
        vm.startPrank(poster);
        vm.expectRevert(ClaudelanceCore.InvalidAmount.selector);
        core.postBounty(0, "x", "x", bytes32(0), 0.1e18, MAX_SLOTS, STAKE, DEADLINE, true);

        vm.expectRevert(ClaudelanceCore.InvalidSlots.selector);
        core.postBounty(0, "x", "x", bytes32(0), AMOUNT, 0, STAKE, DEADLINE, true);

        vm.expectRevert(ClaudelanceCore.InvalidSlots.selector);
        core.postBounty(0, "x", "x", bytes32(0), AMOUNT, 21, STAKE, DEADLINE, true);

        vm.expectRevert(ClaudelanceCore.InvalidDeadline.selector);
        core.postBounty(0, "x", "x", bytes32(0), AMOUNT, MAX_SLOTS, STAKE, 1 hours, true);

        vm.expectRevert(ClaudelanceCore.InvalidDeadline.selector);
        core.postBounty(0, "x", "x", bytes32(0), AMOUNT, MAX_SLOTS, STAKE, 30 days, true);

        vm.expectRevert(ClaudelanceCore.InvalidAddress.selector);
        core.postBounty(0, "", "x", bytes32(0), AMOUNT, MAX_SLOTS, STAKE, DEADLINE, true);
        vm.stopPrank();
    }

    function test_ClaimSlot_LocksStakeAndIncrements() public {
        uint256 id = _post();
        uint256 before = cusd.balanceOf(w1);
        _claim(id, w1);
        assertEq(cusd.balanceOf(w1), before - STAKE);
        assertTrue(core.hasClaimed(id, w1));
        IClaudelanceCore.Bounty memory b = core.getBounty(id);
        assertEq(b.claimedSlots, 1);
        assertEq(core.uniqueWorkerCount(), 1);
    }

    function test_ClaimSlot_RevertsWhenSlotsFull() public {
        uint256 id = _post();
        address[5] memory workers = [w1, w2, w3, makeAddr("w4"), makeAddr("w5")];
        for (uint256 i = 0; i < workers.length; i++) {
            cusd.mint(workers[i], STAKE);
            vm.prank(workers[i]);
            cusd.approve(address(core), STAKE);
            _claim(id, workers[i]);
        }
        address w6 = makeAddr("w6");
        cusd.mint(w6, STAKE);
        vm.prank(w6);
        cusd.approve(address(core), STAKE);
        vm.expectRevert(ClaudelanceCore.SlotsFull.selector);
        vm.prank(w6);
        core.claimSlot(id);
    }

    function test_ClaimSlot_RevertsOnDoubleClaim() public {
        uint256 id = _post();
        _claim(id, w1);
        vm.expectRevert(ClaudelanceCore.AlreadyClaimed.selector);
        vm.prank(w1);
        core.claimSlot(id);
    }

    function test_ClaimSlot_RevertsAfterDeadline() public {
        uint256 id = _post();
        vm.warp(block.timestamp + DEADLINE + 1);
        vm.expectRevert(ClaudelanceCore.DeadlinePassed.selector);
        vm.prank(w1);
        core.claimSlot(id);
    }

    function test_SubmitPR_StoresSubmission() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);
        IClaudelanceCore.Submission memory s = core.getSubmission(id, w1);
        assertEq(s.prUrl, "github.com/employer/repo/pull/2");
        assertEq(s.commitHash, bytes32(uint256(0xabc)));
        assertGt(s.submittedAt, 0);
    }

    function test_SubmitPR_RevertsForNonClaimer() public {
        uint256 id = _post();
        vm.expectRevert(ClaudelanceCore.NotClaimer.selector);
        vm.prank(w1);
        core.submitPR(id, "github.com/x/y/pull/1", bytes32(0), "{}");
    }

    function test_AttestCI_OnlyRelayer() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);
        vm.expectRevert(ClaudelanceCore.NotRelayer.selector);
        vm.prank(stranger);
        core.attestCI(id, w1, true);

        _attest(id, w1, true);
        IClaudelanceCore.Submission memory s = core.getSubmission(id, w1);
        assertTrue(s.ciPassed);
    }

    function test_AttestCI_FailsBeforeSubmission() public {
        uint256 id = _post();
        _claim(id, w1);
        vm.expectRevert(ClaudelanceCore.NoSubmission.selector);
        _attest(id, w1, true);
    }

    function test_PickWinner_FeeMathAndPayouts() public {
        uint256 id = _post();
        _claim(id, w1);
        _claim(id, w2);
        _submit(id, w1);
        _submit(id, w2);
        _attest(id, w1, true);
        _attest(id, w2, true);

        uint256 treasuryBefore = cusd.balanceOf(treasury);

        vm.prank(poster);
        core.pickWinner(id, w1);

        uint96 expectedFee = uint96((uint256(AMOUNT) * 200) / 10_000);
        uint96 expectedPayout = AMOUNT - expectedFee;

        assertEq(cusd.balanceOf(treasury), treasuryBefore + expectedFee);
        assertEq(core.earnings(w1), uint256(expectedPayout) + STAKE);
        assertEq(core.earnings(w2), STAKE);
        assertEq(core.totalProtocolRevenue(), expectedFee);
        assertEq(core.totalBountiesResolved(), 1);

        IClaudelanceCore.Bounty memory b = core.getBounty(id);
        assertEq(uint8(b.status), uint8(IClaudelanceCore.BountyStatus.Resolved));
        assertEq(b.winner, w1);
    }

    function test_PickWinner_OnlyPoster() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);
        _attest(id, w1, true);
        vm.expectRevert(ClaudelanceCore.NotPoster.selector);
        vm.prank(stranger);
        core.pickWinner(id, w1);
    }

    function test_PickWinner_WinnerMustBeEligible() public {
        uint256 id = _post();
        _claim(id, w1);
        vm.expectRevert(ClaudelanceCore.WinnerInvalid.selector);
        vm.prank(poster);
        core.pickWinner(id, w1);

        _submit(id, w1);
        vm.expectRevert(ClaudelanceCore.WinnerInvalid.selector);
        vm.prank(poster);
        core.pickWinner(id, w1);

        _attest(id, w1, false);
        vm.expectRevert(ClaudelanceCore.WinnerInvalid.selector);
        vm.prank(poster);
        core.pickWinner(id, w1);

        vm.expectRevert(ClaudelanceCore.WinnerInvalid.selector);
        vm.prank(poster);
        core.pickWinner(id, w2);
    }

    function test_PickWinner_GoodFaithRefundsAndForfeits() public {
        uint256 id = _post();
        _claim(id, w1);
        _claim(id, w2);
        _claim(id, w3);
        _submit(id, w1);
        _submit(id, w2);
        _submit(id, w3);
        _attest(id, w1, true);
        _attest(id, w2, true);
        _attest(id, w3, false);

        uint256 treasuryBefore = cusd.balanceOf(treasury);

        vm.prank(poster);
        core.pickWinner(id, w1);

        uint96 fee = uint96((uint256(AMOUNT) * 200) / 10_000);
        assertEq(core.earnings(w1), uint256(AMOUNT - fee) + STAKE);
        assertEq(core.earnings(w2), STAKE);
        assertEq(core.earnings(w3), 0);
        assertEq(cusd.balanceOf(treasury), treasuryBefore + fee + STAKE);
    }

    function test_PickWinner_NoStakeNoForfeit() public {
        vm.prank(poster);
        uint256 id = core.postBounty(
            0, "github.com/x/y", "github.com/x/y/issues/1", bytes32(0), AMOUNT, MAX_SLOTS, 0, DEADLINE, false
        );
        _claim(id, w1);
        vm.prank(w1);
        core.submitPR(id, "github.com/x/y/pull/3", bytes32(0), "");

        vm.prank(poster);
        core.pickWinner(id, w1);

        IClaudelanceCore.Bounty memory b = core.getBounty(id);
        assertEq(uint8(b.status), uint8(IClaudelanceCore.BountyStatus.Resolved));
    }

    function test_WithdrawEarnings_PaysAndClears() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);
        _attest(id, w1, true);
        vm.prank(poster);
        core.pickWinner(id, w1);

        uint256 expected = core.earnings(w1);
        uint256 before = cusd.balanceOf(w1);
        vm.prank(w1);
        core.withdrawEarnings();
        assertEq(cusd.balanceOf(w1), before + expected);
        assertEq(core.earnings(w1), 0);

        vm.expectRevert(ClaudelanceCore.NothingToWithdraw.selector);
        vm.prank(w1);
        core.withdrawEarnings();
    }

    function test_CancelExpired_RefundsAndForfeits() public {
        uint256 id = _post();
        _claim(id, w1);
        _claim(id, w2);
        _submit(id, w1);
        _attest(id, w1, true);

        vm.expectRevert(ClaudelanceCore.BountyNotExpired.selector);
        core.cancelExpired(id);

        vm.warp(block.timestamp + DEADLINE + 1);
        uint256 posterBefore = cusd.balanceOf(poster);
        uint256 treasuryBefore = cusd.balanceOf(treasury);

        core.cancelExpired(id);

        assertEq(cusd.balanceOf(poster), posterBefore + AMOUNT);
        assertEq(core.earnings(w1), STAKE);
        assertEq(core.earnings(w2), 0);
        assertEq(cusd.balanceOf(treasury), treasuryBefore + STAKE);

        IClaudelanceCore.Bounty memory b = core.getBounty(id);
        assertEq(uint8(b.status), uint8(IClaudelanceCore.BountyStatus.Cancelled));
    }

    function test_Pause_BlocksNewBountiesButAllowsResolution() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);
        _attest(id, w1, true);

        vm.prank(owner);
        core.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(poster);
        core.postBounty(
            0, "github.com/x/y", "github.com/x/y/issues/1", bytes32(0), AMOUNT, MAX_SLOTS, STAKE, DEADLINE, true
        );

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(w2);
        core.claimSlot(id);

        vm.prank(poster);
        core.pickWinner(id, w1);
        IClaudelanceCore.Bounty memory b = core.getBounty(id);
        assertEq(uint8(b.status), uint8(IClaudelanceCore.BountyStatus.Resolved));
    }

    function test_OnlyOwnerCanPauseAndSet() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        core.pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        core.setTreasury(stranger);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        core.setCIRelayer(stranger);

        vm.startPrank(owner);
        core.setTreasury(makeAddr("newT"));
        core.setCIRelayer(makeAddr("newR"));
        vm.stopPrank();
        assertEq(core.treasury(), makeAddr("newT"));
        assertEq(core.ciRelayer(), makeAddr("newR"));
    }

    function test_Stats_IncrementsCorrectly() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);
        _attest(id, w1, true);
        vm.prank(poster);
        core.pickWinner(id, w1);

        (uint256 vol, uint256 rev, uint256 res, uint256 posters, uint256 workers) = core.getStats();
        assertEq(vol, AMOUNT);
        uint96 fee = uint96((uint256(AMOUNT) * 200) / 10_000);
        assertEq(rev, fee);
        assertEq(res, 1);
        assertEq(posters, 1);
        assertEq(workers, 1);
    }

    function test_GetEligibleSubmissions_FiltersCorrectly() public {
        uint256 id = _post();
        _claim(id, w1);
        _claim(id, w2);
        _claim(id, w3);
        _submit(id, w1);
        _submit(id, w2);
        _attest(id, w1, true);
        _attest(id, w2, false);

        address[] memory eligible = core.getEligibleSubmissions(id);
        assertEq(eligible.length, 1);
        assertEq(eligible[0], w1);
    }

    function test_DoubleResolveReverts() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);
        _attest(id, w1, true);
        vm.prank(poster);
        core.pickWinner(id, w1);
        vm.expectRevert(ClaudelanceCore.BountyNotOpen.selector);
        vm.prank(poster);
        core.pickWinner(id, w1);
    }

    function test_BountyTypeAcceptsAnyUint8() public {
        vm.prank(poster);
        uint256 id = core.postBounty(
            7, "github.com/x/y", "github.com/x/y/issues/1", bytes32(0), AMOUNT, 1, 0, DEADLINE, false
        );
        assertEq(core.bountyCountByType(7), 1);
        IClaudelanceCore.Bounty memory b = core.getBounty(id);
        assertEq(b.bountyType, 7);
    }

    function test_SubmitPR_IsOneShot() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);

        vm.expectRevert(ClaudelanceCore.AlreadySubmitted.selector);
        vm.prank(w1);
        core.submitPR(id, "github.com/employer/repo/pull/99", bytes32(uint256(0xdef)), "{}");

        IClaudelanceCore.Submission memory s = core.getSubmission(id, w1);
        assertEq(s.prUrl, "github.com/employer/repo/pull/2");
        assertEq(s.commitHash, bytes32(uint256(0xabc)));
    }

    function test_SubmitPR_OneShot_PreventsCIBypass() public {
        uint256 id = _post();
        _claim(id, w1);
        _submit(id, w1);
        _attest(id, w1, true);

        vm.expectRevert(ClaudelanceCore.AlreadySubmitted.selector);
        vm.prank(w1);
        core.submitPR(id, "github.com/employer/repo/pull/666", bytes32(uint256(0xbad)), "malicious");

        IClaudelanceCore.Submission memory s = core.getSubmission(id, w1);
        assertTrue(s.ciPassed);
        assertEq(s.prUrl, "github.com/employer/repo/pull/2");
    }
}
