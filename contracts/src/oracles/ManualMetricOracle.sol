// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IMetricOracle} from "../interfaces/IMetricOracle.sol";

/// @title  ManualMetricOracle
/// @notice A trivially-trusted oracle that lets a designated reporter address
///         set the metric value for any issueId. Used in Helm v0 testing and
///         as a building block for prototypes.
///
/// @dev    **NOT FOR PRODUCTION USE WITH REAL VALUE AT STAKE.** The reporter
///         can set arbitrary values without challenge. Real deployments should
///         use a validator-network oracle (e.g., a Crucible TestcaseResolverV5
///         adapter, planned for Helm v0.2) or a Chainlink-style adapter.
///
/// @dev    No admin keys beyond the immutable reporter address. To rotate the
///         reporter, deploy a new oracle.
contract ManualMetricOracle is IMetricOracle {
    /// @notice The single address authorized to report metrics. Immutable.
    address public immutable reporter;

    mapping(bytes32 => uint256) public metrics;
    mapping(bytes32 => bool) public reported;

    event MetricReported(bytes32 indexed issueId, uint256 value);

    error NotReporter();
    error AlreadyReported();
    error NotReported();

    constructor(address _reporter) {
        require(_reporter != address(0), "reporter zero");
        reporter = _reporter;
    }

    function reportMetric(bytes32 issueId, uint256 value) external {
        if (msg.sender != reporter) revert NotReporter();
        if (reported[issueId]) revert AlreadyReported();
        metrics[issueId] = value;
        reported[issueId] = true;
        emit MetricReported(issueId, value);
    }

    /* ----- IMetricOracle ----- */

    function isReady(bytes32 issueId) external view returns (bool) {
        return reported[issueId];
    }

    function getMetric(bytes32 issueId, bytes calldata) external view returns (uint256) {
        if (!reported[issueId]) revert NotReported();
        return metrics[issueId];
    }
}
