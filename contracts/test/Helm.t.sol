// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Helm} from "../src/Helm.sol";
import {ManualMetricOracle} from "../src/oracles/ManualMetricOracle.sol";

contract HelmTest is Test {
    Helm helm;
    ManualMetricOracle oracle;

    address proposer = makeAddr("proposer");
    address alice    = makeAddr("alice");
    address bob      = makeAddr("bob");
    address carol    = makeAddr("carol");
    address reporter = makeAddr("reporter");

    // helpers
    uint8 constant X     = 0;
    uint8 constant NOT_X = 1;
    uint8 constant YES   = 0;
    uint8 constant NO    = 1;

    bytes32 constant METRIC_KEY = bytes32("test-metric");

    function setUp() public {
        helm = new Helm();
        oracle = new ManualMetricOracle(reporter);
        vm.deal(proposer, 100 ether);
        vm.deal(alice,    100 ether);
        vm.deal(bob,      100 ether);
        vm.deal(carol,    100 ether);
        vm.warp(1_000_000);
    }

    /* ---------- helper: propose with sensible defaults ---------- */

    function _propose(uint256 threshold, uint8 defaultDecision) internal returns (bytes32 issueId) {
        vm.prank(proposer);
        issueId = helm.proposeIssue(
            address(oracle),
            METRIC_KEY,
            threshold,
            uint64(block.timestamp + 1 hours),     // decideAt
            uint64(block.timestamp + 2 hours),     // resolveAt
            defaultDecision
        );
    }

    function _bet(address who, bytes32 issueId, uint8 branch, uint8 side, uint256 amount) internal {
        vm.prank(who);
        helm.bet{value: amount}(issueId, branch, side);
    }

    /* ============================================================ */
    /*                       proposeIssue                            */
    /* ============================================================ */

    function test_propose_happyPath() public {
        bytes32 issueId = _propose(100, X);
        (
            address p,
            address mo,
            bytes32 mk,
            uint256 th,
            uint64 dec,
            uint64 res,
            uint8 def,
            Helm.Status status,
            uint8 chosen,
            bool met,
            uint256 value
        ) = helm.issues(issueId);
        assertEq(p, proposer);
        assertEq(mo, address(oracle));
        assertEq(mk, METRIC_KEY);
        assertEq(th, 100);
        assertEq(uint256(status), uint256(Helm.Status.Open));
        assertEq(def, X);
        assertEq(chosen, 0);
        assertFalse(met);
        assertEq(value, 0);
        assertEq(dec, block.timestamp + 1 hours);
        assertEq(res, block.timestamp + 2 hours);
    }

    function test_propose_revertsOnPastDecide() public {
        vm.prank(proposer);
        vm.expectRevert(Helm.InvalidTimes.selector);
        helm.proposeIssue(address(oracle), METRIC_KEY, 100, uint64(block.timestamp), uint64(block.timestamp + 1 hours), X);
    }

    function test_propose_revertsOnDecideAfterResolve() public {
        vm.prank(proposer);
        vm.expectRevert(Helm.InvalidTimes.selector);
        helm.proposeIssue(address(oracle), METRIC_KEY, 100,
            uint64(block.timestamp + 2 hours), uint64(block.timestamp + 1 hours), X);
    }

    function test_propose_revertsOnBadDefaultDecision() public {
        vm.prank(proposer);
        vm.expectRevert(Helm.InvalidDefault.selector);
        helm.proposeIssue(address(oracle), METRIC_KEY, 100,
            uint64(block.timestamp + 1 hours), uint64(block.timestamp + 2 hours), 2);
    }

    function test_propose_distinctIssueIds() public {
        bytes32 a = _propose(100, X);
        bytes32 b = _propose(100, X);
        assertTrue(a != b);
    }

    /* ============================================================ */
    /*                              bet                              */
    /* ============================================================ */

    function test_bet_happyPath() public {
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.01 ether);

        (uint256 xYes,,,) = helm.pools(issueId);
        assertEq(xYes, 0.01 ether);
        assertEq(helm.userBet(issueId, X, YES, alice), 0.01 ether);
    }

    function test_bet_belowMinReverts() public {
        bytes32 issueId = _propose(100, X);
        vm.prank(alice);
        vm.expectRevert(Helm.BetBelowMin.selector);
        helm.bet{value: 0.00001 ether}(issueId, X, YES);
    }

    function test_bet_invalidBranchReverts() public {
        bytes32 issueId = _propose(100, X);
        vm.prank(alice);
        vm.expectRevert(Helm.InvalidBranch.selector);
        helm.bet{value: 0.01 ether}(issueId, 2, YES);
    }

    function test_bet_invalidSideReverts() public {
        bytes32 issueId = _propose(100, X);
        vm.prank(alice);
        vm.expectRevert(Helm.InvalidSide.selector);
        helm.bet{value: 0.01 ether}(issueId, X, 2);
    }

    function test_bet_revertsAfterDecideAt() public {
        bytes32 issueId = _propose(100, X);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        vm.expectRevert(Helm.IssueNotOpen.selector);
        helm.bet{value: 0.01 ether}(issueId, X, YES);
    }

    function test_bet_multipleBetsAccumulate() public {
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.01 ether);
        _bet(alice, issueId, X, YES, 0.02 ether);
        assertEq(helm.userBet(issueId, X, YES, alice), 0.03 ether);
    }

    /* ============================================================ */
    /*                              decide                           */
    /* ============================================================ */

    function test_decide_emptyPoolsUsesDefault() public {
        bytes32 issueId = _propose(100, NOT_X);  // default = NOT_X
        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, NOT_X);
    }

    function test_decide_onlyXHasBetsPicksX() public {
        bytes32 issueId = _propose(100, NOT_X);
        _bet(alice, issueId, X, YES, 0.01 ether);
        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, X);
    }

    function test_decide_onlyNotXHasBetsPicksNotX() public {
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, NOT_X, YES, 0.01 ether);
        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, NOT_X);
    }

    function test_decide_higherPriceWins_X() public {
        bytes32 issueId = _propose(100, NOT_X);
        // P(YES | X)     = 90 / 100 = 0.90
        // P(YES | NOT_X) = 50 / 100 = 0.50
        _bet(alice, issueId, X,     YES, 0.09 ether);
        _bet(alice, issueId, X,     NO,  0.01 ether);
        _bet(bob,   issueId, NOT_X, YES, 0.05 ether);
        _bet(bob,   issueId, NOT_X, NO,  0.05 ether);

        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, X);
    }

    function test_decide_higherPriceWins_NotX() public {
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X,     YES, 0.02 ether);
        _bet(alice, issueId, X,     NO,  0.08 ether);
        _bet(bob,   issueId, NOT_X, YES, 0.07 ether);
        _bet(bob,   issueId, NOT_X, NO,  0.03 ether);

        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, NOT_X);
    }

    function test_decide_tieUsesDefault() public {
        bytes32 issueId = _propose(100, NOT_X);
        // Equal prices
        _bet(alice, issueId, X,     YES, 0.05 ether);
        _bet(alice, issueId, X,     NO,  0.05 ether);
        _bet(bob,   issueId, NOT_X, YES, 0.05 ether);
        _bet(bob,   issueId, NOT_X, NO,  0.05 ether);
        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, NOT_X);
    }

    function test_decide_tooEarlyReverts() public {
        bytes32 issueId = _propose(100, X);
        vm.expectRevert(Helm.DecideTooEarly.selector);
        helm.decide(issueId);
    }

    function test_decide_doubleDecideReverts() public {
        bytes32 issueId = _propose(100, X);
        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        vm.expectRevert(Helm.IssueNotOpen.selector);
        helm.decide(issueId);
    }

    /* ============================================================ */
    /*                              resolve                          */
    /* ============================================================ */

    function test_resolve_metricMet() public {
        uint256 t0 = block.timestamp;
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.01 ether);
        vm.warp(t0 + 1 hours + 1);
        helm.decide(issueId);

        vm.prank(reporter);
        oracle.reportMetric(issueId, 150);
        vm.warp(t0 + 2 hours + 1);
        helm.resolve(issueId, "");
        (,,,,,,,,,bool met, uint256 v) = helm.issues(issueId);
        assertTrue(met);
        assertEq(v, 150);
    }

    function test_resolve_metricNotMet() public {
        uint256 t0 = block.timestamp;
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, NO, 0.01 ether);
        vm.warp(t0 + 1 hours + 1);
        helm.decide(issueId);
        vm.prank(reporter);
        oracle.reportMetric(issueId, 50);
        vm.warp(t0 + 2 hours + 1);
        helm.resolve(issueId, "");
        (,,,,,,,,,bool met,) = helm.issues(issueId);
        assertFalse(met);
    }

    function test_resolve_revertsIfNotReady() public {
        uint256 t0 = block.timestamp;
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.01 ether);
        vm.warp(t0 + 1 hours + 1);
        helm.decide(issueId);
        vm.warp(t0 + 2 hours + 1);
        vm.expectRevert(Helm.OracleNotReady.selector);
        helm.resolve(issueId, "");
    }

    function test_resolve_revertsTooEarly() public {
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.01 ether);
        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        vm.prank(reporter);
        oracle.reportMetric(issueId, 150);
        // not warping past resolveAt
        vm.expectRevert(Helm.ResolveTooEarly.selector);
        helm.resolve(issueId, "");
    }

    /* ============================================================ */
    /*                              claim                            */
    /* ============================================================ */

    function test_claim_rejectedBranchRefunds() public {
        bytes32 issueId = _propose(100, X);
        // alice bets only on NOT_X
        _bet(alice, issueId, NOT_X, YES, 0.05 ether);
        _bet(alice, issueId, NOT_X, NO,  0.03 ether);
        // bob bets only on X (so X gets chosen — it has higher YES price)
        _bet(bob, issueId, X, YES, 0.01 ether);

        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);  // X wins (NOT_X has lower P(YES)=5/8 vs X=1/1)

        uint256 aliceBalBefore = alice.balance;
        vm.prank(alice);
        helm.claim(issueId);
        // Full refund of 0.08 ether
        assertEq(alice.balance, aliceBalBefore + 0.08 ether);
    }

    function test_claim_chosenBranch_yesWinsAndSplitsLoserPool() public {
        uint256 t0 = block.timestamp;
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.06 ether);
        _bet(bob,   issueId, X, NO,  0.05 ether);

        vm.warp(t0 + 1 hours + 1);
        helm.decide(issueId);

        vm.prank(reporter);
        oracle.reportMetric(issueId, 150);
        vm.warp(t0 + 2 hours + 1);
        helm.resolve(issueId, "");

        uint256 aliceBalBefore = alice.balance;
        vm.prank(alice);
        helm.claim(issueId);
        assertEq(alice.balance, aliceBalBefore + 0.11 ether);

        vm.prank(bob);
        vm.expectRevert(Helm.NothingToClaim.selector);
        helm.claim(issueId);
    }

    function test_claim_chosenBranch_noWinsAndSplitsLoserPool() public {
        uint256 t0 = block.timestamp;
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.06 ether);
        _bet(bob,   issueId, X, NO,  0.05 ether);
        vm.warp(t0 + 1 hours + 1);
        helm.decide(issueId);
        vm.prank(reporter);
        oracle.reportMetric(issueId, 50);
        vm.warp(t0 + 2 hours + 1);
        helm.resolve(issueId, "");

        uint256 bobBalBefore = bob.balance;
        vm.prank(bob);
        helm.claim(issueId);
        assertEq(bob.balance, bobBalBefore + 0.11 ether);
    }

    function test_claim_proRataBetweenMultipleWinners() public {
        uint256 t0 = block.timestamp;
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.02 ether);
        _bet(carol, issueId, X, YES, 0.04 ether);
        _bet(bob,   issueId, X, NO,  0.03 ether);

        vm.warp(t0 + 1 hours + 1);
        helm.decide(issueId);
        vm.prank(reporter);
        oracle.reportMetric(issueId, 200);
        vm.warp(t0 + 2 hours + 1);
        helm.resolve(issueId, "");

        uint256 aliceBefore = alice.balance;
        uint256 carolBefore = carol.balance;

        vm.prank(alice); helm.claim(issueId);
        vm.prank(carol); helm.claim(issueId);

        assertEq(alice.balance, aliceBefore + 0.03 ether);
        assertEq(carol.balance, carolBefore + 0.06 ether);
    }

    function test_claim_revertsIfNothing() public {
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X, YES, 0.01 ether);
        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);
        // Bob never bet
        vm.prank(bob);
        vm.expectRevert(Helm.NothingToClaim.selector);
        helm.claim(issueId);
    }

    function test_claim_idempotent_doubleCallReverts() public {
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, NOT_X, YES, 0.01 ether);
        _bet(bob,   issueId, X,     YES, 0.01 ether);
        vm.warp(block.timestamp + 1 hours + 1);
        helm.decide(issueId);  // X wins (NOT_X has bets only on YES, lone-branch picks NOT_X actually... wait)

        // Actually: X has 0.01 YES, 0 NO → P(YES|X)=1.0
        //         NOT_X has 0.01 YES, 0 NO → P(YES|NOT_X)=1.0
        // Tie → default decision = X
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, X);

        // alice (NOT_X bet) gets full refund
        vm.prank(alice);
        uint256 first = helm.claim(issueId);
        assertEq(first, 0.01 ether);

        // Double-claim should revert
        vm.prank(alice);
        vm.expectRevert(Helm.NothingToClaim.selector);
        helm.claim(issueId);
    }

    function test_claim_partialClaimRejectedThenChosen() public {
        uint256 t0 = block.timestamp;
        bytes32 issueId = _propose(100, X);
        _bet(alice, issueId, X,     YES, 0.05 ether);
        _bet(alice, issueId, NOT_X, NO,  0.03 ether);
        _bet(bob,   issueId, X,     NO,  0.05 ether);

        vm.warp(t0 + 1 hours + 1);
        helm.decide(issueId);
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, X);

        uint256 before = alice.balance;
        vm.prank(alice);
        uint256 paid1 = helm.claim(issueId);
        assertEq(paid1, 0.03 ether);
        assertEq(alice.balance, before + 0.03 ether);

        vm.prank(reporter);
        oracle.reportMetric(issueId, 200);
        vm.warp(t0 + 2 hours + 1);
        helm.resolve(issueId, "");

        before = alice.balance;
        vm.prank(alice);
        uint256 paid2 = helm.claim(issueId);
        assertEq(paid2, 0.10 ether);
        assertEq(alice.balance, before + 0.10 ether);

        vm.prank(alice);
        vm.expectRevert(Helm.NothingToClaim.selector);
        helm.claim(issueId);
    }

    /* ============================================================ */
    /*                       end-to-end happy path                   */
    /* ============================================================ */

    function test_endToEnd_fullLifecycle() public {
        // Issue: "Should agent DAO adopt strategy X?"
        // Setup: alice X-YES 0.10, alice X-NO 0.02 → P=0.833
        //        bob NOT_X-YES 0.04, bob NOT_X-NO 0.02 → P=0.667
        // X should win.
        uint256 t0 = block.timestamp;
        bytes32 issueId = _propose(1000, NOT_X);

        _bet(alice, issueId, X,     YES, 0.10 ether);
        _bet(alice, issueId, X,     NO,  0.02 ether);
        _bet(bob,   issueId, NOT_X, YES, 0.04 ether);
        _bet(bob,   issueId, NOT_X, NO,  0.02 ether);

        (uint256 pX, uint256 pNotX) = helm.prices(issueId);
        assertGt(pX, pNotX);

        vm.warp(t0 + 1 hours + 1);
        helm.decide(issueId);
        (,,,,,,,, uint8 chosen,,) = helm.issues(issueId);
        assertEq(chosen, X);

        vm.prank(reporter);
        oracle.reportMetric(issueId, 1500);
        vm.warp(t0 + 2 hours + 1);
        helm.resolve(issueId, "");

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        helm.claim(issueId);
        assertEq(bob.balance, bobBefore + 0.06 ether);

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        helm.claim(issueId);
        assertEq(alice.balance, aliceBefore + 0.12 ether);
    }
}
