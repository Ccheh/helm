// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title  IMetricOracle
/// @notice A metric oracle reports a single uint256 value per issueId at the
///         time the issue is resolved by Helm. The value is compared against
///         the issue's threshold to decide whether YES bets win (value >
///         threshold) or NO bets win (value <= threshold).
///
/// @dev    Helm calls `isReady` before resolving — if false, resolution waits.
///         `getMetric` is called once at resolution time. Oracles may be:
///           - manually reported (see `ManualMetricOracle.sol`, v0 default)
///           - validator-network-resolved (Crucible TestcaseResolverV5 adapter
///             — planned for v0.2 of Helm)
///           - Chainlink / Pyth feed adapters
///           - ZK-attested computation outputs
///
/// @dev    Oracles are NOT trusted by Helm beyond the value they return. Helm
///         does no further validation. Operators of agent DAOs must choose
///         oracles they trust for the metric in question.
interface IMetricOracle {
    /// @notice Whether the oracle is ready to report a metric for this issue.
    function isReady(bytes32 issueId) external view returns (bool);

    /// @notice Returns the metric value for the issue. Reverts if not ready.
    /// @dev    `data` is opaque oracle-specific payload (e.g., bytes proof, or
    ///         empty for manual oracles).
    function getMetric(bytes32 issueId, bytes calldata data) external view returns (uint256);
}
