// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IMetricOracle} from "../interfaces/IMetricOracle.sol";

/// @notice Minimal external view into a CrucibleMarketV6 deployment. Only the
///         `markets(bytes32)` storage getter is needed for the adapter; we do
///         not need any state-changing function or any other view.
/// @dev    Field order MUST match the Market struct in CrucibleMarketV6.sol
///         (otherwise the auto-generated getter's return order mismatches
///         and Solidity will refuse to compile).
interface ICrucibleMarketV6 {
    function markets(bytes32 marketId) external view returns (
        address service,
        address agent,
        address resolver,
        uint256 agentEscrow,
        uint256 bondLocked,
        uint256 disputeBond,
        uint16 disputeBondBps,
        bytes32 commitmentHash,
        uint64 disputeDeadline,
        uint64 disputedAt,
        uint16 scoreBps,
        uint8 status
    );
}

/// @title  CrucibleMetricOracle
/// @notice Adapts a CrucibleMarketV6's per-call quality score into the
///         IMetricOracle interface Helm consumes. This is the realisation of
///         the cross-protocol bridge previously described as "planned for
///         Helm v0.2" — letting an agent collective's futarchy decision
///         resolve on a metric the Crucible validator network has voted on.
///
///         Lifecycle (off-chain orchestration):
///           1. Helm proposer calls `proposeIssue(crucibleMetricOracle, ...)`.
///           2. Off chain, the agent collective conducts a Crucible-mediated
///              evaluation: open a CrucibleMarketV6 market, run validators,
///              dispute / resolve, end at a `scoreBps` value in [0, 10000].
///           3. Anyone calls `CrucibleMetricOracle.register(issueId, marketId)`
///              once to bind the Helm issue to the resolved Crucible market.
///           4. Helm calls `resolve(issueId, "")` which queries this adapter
///              for `scoreBps` (returned as the metric value).
///           5. Helm compares `scoreBps` against the issue's `threshold` and
///              decides YES vs NO accordingly.
///
/// @dev    No admin keys. Mapping is permissionless and write-once per
///         issueId. First writer wins. This is acceptable because:
///         - Helm's issueId is a hash of `(proposer, count, chainId)` — the
///           proposer controls who knows about it pre-publication. By the
///           time an attacker sees the issueId, the proposer has had time to
///           call `register()` first.
///         - If a registration races to a wrong market, the proposer can
///           always propose a new issue with the correct binding. The cost
///           of a wrong registration is one issue's bets being refunded as
///           "rejected branch" (Helm semantics: stuck oracle → forever
///           pending until forceResolveStale equivalent, which Helm v0
///           lacks — note this in honest limits).
contract CrucibleMetricOracle is IMetricOracle {
    /// @notice The CrucibleMarketV6 deployment this adapter reads from.
    ICrucibleMarketV6 public immutable crucibleMarket;

    /// @notice The Crucible v0.6 enum value for a resolved market. Mirrors
    ///         `Status.Resolved` (= 3) in CrucibleMarketV6.sol. Hardcoded as a
    ///         constant so this adapter does not need to import the enum.
    uint8 public constant CRUCIBLE_STATUS_RESOLVED = 3;

    /// @notice Helm issueId => Crucible marketId. Set once via `register`.
    mapping(bytes32 => bytes32) public marketForIssue;

    event MarketRegistered(bytes32 indexed issueId, bytes32 indexed marketId, address indexed registrar);

    error AlreadyRegistered();
    error NotRegistered();
    error MarketNotResolved();
    error ZeroMarketId();

    constructor(address _crucibleMarket) {
        require(_crucibleMarket != address(0), "market zero");
        crucibleMarket = ICrucibleMarketV6(_crucibleMarket);
    }

    /// @notice Bind a Helm issueId to a Crucible marketId. Callable once per
    ///         issueId; first registration is final.
    function register(bytes32 issueId, bytes32 marketId) external {
        if (marketId == bytes32(0)) revert ZeroMarketId();
        if (marketForIssue[issueId] != bytes32(0)) revert AlreadyRegistered();
        marketForIssue[issueId] = marketId;
        emit MarketRegistered(issueId, marketId, msg.sender);
    }

    /* ---------- IMetricOracle ---------- */

    /// @notice Ready when (a) a marketId has been registered for this issue,
    ///         AND (b) that Crucible market has reached the Resolved state.
    function isReady(bytes32 issueId) external view returns (bool) {
        bytes32 marketId = marketForIssue[issueId];
        if (marketId == bytes32(0)) return false;
        (, , , , , , , , , , , uint8 status) = crucibleMarket.markets(marketId);
        return status == CRUCIBLE_STATUS_RESOLVED;
    }

    /// @notice Returns the resolved market's `scoreBps` as the metric value.
    ///         Range is [0, 10000]. Helm's threshold can be set anywhere in
    ///         that range — e.g., threshold=5000 means "metric > 5000" which
    ///         is YES if the Crucible market resolved above 50% quality.
    /// @dev    The `data` argument is unused; included to satisfy IMetricOracle.
    function getMetric(bytes32 issueId, bytes calldata /* data */) external view returns (uint256) {
        bytes32 marketId = marketForIssue[issueId];
        if (marketId == bytes32(0)) revert NotRegistered();
        (, , , , , , , , , , uint16 scoreBps, uint8 status) = crucibleMarket.markets(marketId);
        if (status != CRUCIBLE_STATUS_RESOLVED) revert MarketNotResolved();
        return uint256(scoreBps);
    }
}
