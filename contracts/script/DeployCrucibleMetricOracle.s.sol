// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CrucibleMetricOracle} from "../src/oracles/CrucibleMetricOracle.sol";

/// @notice Deploys CrucibleMetricOracle pointed at the live CrucibleMarketV6
///         on Arc Testnet. This is the on-chain realisation of the
///         "Crucible's validator network as a Helm metric oracle" composition
///         previously described in Helm's README as planned future work.
///
///         CrucibleMarketV6 address on Arc Testnet:
///           0x6535a3cbb4235746b732ab5d55c6b0988f381a20
///
///         After deployment, callers wire a Helm issue to a Crucible market
///         via `CrucibleMetricOracle.register(issueId, marketId)`. The Helm
///         contract then queries this adapter at resolve time for scoreBps.
contract DeployCrucibleMetricOracleScript is Script {
    address public constant CRUCIBLE_MARKET_V6 = 0x6535a3CbB4235746B732aB5d55c6b0988F381A20;

    function run() external {
        vm.startBroadcast();
        CrucibleMetricOracle oracle = new CrucibleMetricOracle(CRUCIBLE_MARKET_V6);
        vm.stopBroadcast();

        console.log("=== CrucibleMetricOracle deployment ===");
        console.log("Chain ID:             ", block.chainid);
        console.log("CrucibleMetricOracle: ", address(oracle));
        console.log("Adapts:               ", CRUCIBLE_MARKET_V6);
        console.log("Constant resolved:    ", oracle.CRUCIBLE_STATUS_RESOLVED());
    }
}
