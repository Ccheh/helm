// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {CrucibleMetricOracle, ICrucibleMarketV6} from "../src/oracles/CrucibleMetricOracle.sol";
import {Helm} from "../src/Helm.sol";

/// @dev Mock CrucibleMarketV6 that lets the test set the (scoreBps, status)
///      tuple for any marketId. Implements the same `markets(bytes32)` getter
///      signature so the adapter can read from it transparently.
contract MockCrucibleMarketV6 is ICrucibleMarketV6 {
    struct MarketState {
        uint16 scoreBps;
        uint8  status;
    }

    mapping(bytes32 => MarketState) private state;

    function set(bytes32 marketId, uint16 scoreBps, uint8 status) external {
        state[marketId] = MarketState(scoreBps, status);
    }

    function markets(bytes32 marketId) external view returns (
        address, address, address, uint256, uint256, uint256, uint16, bytes32,
        uint64, uint64, uint16, uint8
    ) {
        MarketState memory m = state[marketId];
        return (
            address(0), address(0), address(0),
            0, 0, 0, 0, bytes32(0),
            0, 0,
            m.scoreBps, m.status
        );
    }
}

contract CrucibleMetricOracleTest is Test {
    CrucibleMetricOracle adapter;
    MockCrucibleMarketV6 mockMarket;

    bytes32 constant ISSUE_A = keccak256("issue-a");
    bytes32 constant ISSUE_B = keccak256("issue-b");
    bytes32 constant MARKET_A = keccak256("market-a");
    bytes32 constant MARKET_B = keccak256("market-b");

    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");

    uint8 constant STATUS_NONE     = 0;
    uint8 constant STATUS_OPEN     = 1;
    uint8 constant STATUS_DISPUTED = 2;
    uint8 constant STATUS_RESOLVED = 3;

    function setUp() public {
        mockMarket = new MockCrucibleMarketV6();
        adapter = new CrucibleMetricOracle(address(mockMarket));
    }

    /* ---------- constructor ---------- */

    function test_constructor_revertsOnZeroMarket() public {
        vm.expectRevert(bytes("market zero"));
        new CrucibleMetricOracle(address(0));
    }

    function test_constructor_setsMarket() public view {
        assertEq(address(adapter.crucibleMarket()), address(mockMarket));
    }

    /* ---------- register ---------- */

    function test_register_happyPath() public {
        vm.prank(alice);
        adapter.register(ISSUE_A, MARKET_A);
        assertEq(adapter.marketForIssue(ISSUE_A), MARKET_A);
    }

    function test_register_emitsEvent() public {
        vm.expectEmit(true, true, true, false);
        emit CrucibleMetricOracle.MarketRegistered(ISSUE_A, MARKET_A, alice);
        vm.prank(alice);
        adapter.register(ISSUE_A, MARKET_A);
    }

    function test_register_revertsOnZeroMarketId() public {
        vm.expectRevert(CrucibleMetricOracle.ZeroMarketId.selector);
        adapter.register(ISSUE_A, bytes32(0));
    }

    function test_register_revertsOnAlreadyRegistered() public {
        vm.prank(alice);
        adapter.register(ISSUE_A, MARKET_A);
        vm.prank(bob);
        vm.expectRevert(CrucibleMetricOracle.AlreadyRegistered.selector);
        adapter.register(ISSUE_A, MARKET_B);
    }

    function test_register_permissionlessFirstWriterWins() public {
        // Alice and Bob both want to bind ISSUE_A; alice gets there first.
        vm.prank(alice);
        adapter.register(ISSUE_A, MARKET_A);
        vm.prank(bob);
        vm.expectRevert(CrucibleMetricOracle.AlreadyRegistered.selector);
        adapter.register(ISSUE_A, MARKET_B);
        // Mapping unchanged.
        assertEq(adapter.marketForIssue(ISSUE_A), MARKET_A);
    }

    function test_register_differentIssuesIndependent() public {
        vm.prank(alice);
        adapter.register(ISSUE_A, MARKET_A);
        vm.prank(bob);
        adapter.register(ISSUE_B, MARKET_B);
        assertEq(adapter.marketForIssue(ISSUE_A), MARKET_A);
        assertEq(adapter.marketForIssue(ISSUE_B), MARKET_B);
    }

    /* ---------- isReady ---------- */

    function test_isReady_falseBeforeRegister() public view {
        assertEq(adapter.isReady(ISSUE_A), false);
    }

    function test_isReady_falseWhenMarketStillOpen() public {
        adapter.register(ISSUE_A, MARKET_A);
        mockMarket.set(MARKET_A, 0, STATUS_OPEN);
        assertEq(adapter.isReady(ISSUE_A), false);
    }

    function test_isReady_falseWhenMarketDisputed() public {
        adapter.register(ISSUE_A, MARKET_A);
        mockMarket.set(MARKET_A, 0, STATUS_DISPUTED);
        assertEq(adapter.isReady(ISSUE_A), false);
    }

    function test_isReady_trueWhenMarketResolved() public {
        adapter.register(ISSUE_A, MARKET_A);
        mockMarket.set(MARKET_A, 7500, STATUS_RESOLVED);
        assertEq(adapter.isReady(ISSUE_A), true);
    }

    /* ---------- getMetric ---------- */

    function test_getMetric_revertsBeforeRegister() public {
        vm.expectRevert(CrucibleMetricOracle.NotRegistered.selector);
        adapter.getMetric(ISSUE_A, "");
    }

    function test_getMetric_revertsBeforeResolved() public {
        adapter.register(ISSUE_A, MARKET_A);
        mockMarket.set(MARKET_A, 5000, STATUS_OPEN);
        vm.expectRevert(CrucibleMetricOracle.MarketNotResolved.selector);
        adapter.getMetric(ISSUE_A, "");
    }

    function test_getMetric_returnsScoreBpsAtZero() public {
        adapter.register(ISSUE_A, MARKET_A);
        mockMarket.set(MARKET_A, 0, STATUS_RESOLVED);
        assertEq(adapter.getMetric(ISSUE_A, ""), 0);
    }

    function test_getMetric_returnsScoreBpsAtMax() public {
        adapter.register(ISSUE_A, MARKET_A);
        mockMarket.set(MARKET_A, 10000, STATUS_RESOLVED);
        assertEq(adapter.getMetric(ISSUE_A, ""), 10000);
    }

    function test_getMetric_returnsScoreBpsMidRange() public {
        adapter.register(ISSUE_A, MARKET_A);
        mockMarket.set(MARKET_A, 6750, STATUS_RESOLVED);
        assertEq(adapter.getMetric(ISSUE_A, ""), 6750);
    }

    function test_getMetric_ignoresDataArgument() public {
        adapter.register(ISSUE_A, MARKET_A);
        mockMarket.set(MARKET_A, 4321, STATUS_RESOLVED);
        // Adapter must ignore arbitrary `data` bytes
        assertEq(adapter.getMetric(ISSUE_A, hex"deadbeef"), 4321);
        assertEq(adapter.getMetric(ISSUE_A, ""), 4321);
    }

    /* ---------- end-to-end with Helm ---------- */

    /// @dev Plug the adapter into a real Helm contract and walk a full
    ///      issue lifecycle (propose → bet → decide → resolve → claim)
    ///      where the metric comes from a (mocked) Crucible market scoreBps.
    function test_endToEnd_helmResolvesFromCrucibleScore() public {
        Helm helm = new Helm();

        address proposer = makeAddr("e2e-proposer");
        address agent    = makeAddr("e2e-agent");
        vm.deal(proposer, 10 ether);
        vm.deal(agent, 10 ether);

        uint64 t0 = 1_000_000;
        vm.warp(t0);

        uint64 decideAt  = t0 + 1 hours;
        uint64 resolveAt = t0 + 2 hours;

        // proposer creates an issue: "is the Crucible-attested score > 5000?"
        vm.prank(proposer);
        bytes32 issueId = helm.proposeIssue(
            address(adapter),
            keccak256("test-metric"),
            5000,        // threshold
            decideAt,
            resolveAt,
            0            // default = X
        );

        // proposer bets on X-YES, agent on X-NO
        vm.prank(proposer);
        helm.bet{value: 0.01 ether}(issueId, 0, 0); // X-YES
        vm.prank(agent);
        helm.bet{value: 0.005 ether}(issueId, 0, 1); // X-NO
        // p_X = 0.01 / 0.015 ≈ 0.67  — X chosen (no NOT_X bets)

        vm.warp(decideAt + 1);
        helm.decide(issueId);

        // Off-chain: a Crucible market is opened, validators vote, market resolves at score 7500.
        bytes32 marketId = keccak256("crucible-market-for-e2e-test");
        mockMarket.set(marketId, 7500, STATUS_RESOLVED);

        // Anyone (we use proposer) registers the binding on the adapter.
        vm.prank(proposer);
        adapter.register(issueId, marketId);

        // Now resolve Helm — should query adapter, see scoreBps=7500 > 5000 → YES wins on X branch
        vm.warp(resolveAt + 1);
        helm.resolve(issueId, "");

        (, , , , , , , Helm.Status status, , bool met, uint256 value) = helm.issues(issueId);
        assertEq(uint256(status), uint256(Helm.Status.Resolved));
        assertEq(met, true);
        assertEq(value, 7500);

        // proposer (X-YES bettor) claims winnings
        vm.prank(proposer);
        uint256 payout = helm.claim(issueId);
        // payout = principal (0.01) + share of X-NO pool (0.005)
        assertEq(payout, 0.015 ether);
    }
}
