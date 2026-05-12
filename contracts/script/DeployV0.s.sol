// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Helm} from "../src/Helm.sol";
import {ManualMetricOracle} from "../src/oracles/ManualMetricOracle.sol";

/// @notice Deploys the v0 stack to Arc Testnet:
///         - Helm.sol (core futarchy contract)
///         - ManualMetricOracle.sol (v0 test oracle; reporter = deployer)
///
///         The reporter address controls metric reports — for the testnet
///         demo we set it to the deployer. Production deployments would
///         use a more robust IMetricOracle (Chainlink adapter, Crucible
///         TestcaseResolverV5 adapter, etc.).
contract DeployV0Script is Script {
    function run() external {
        address deployer = msg.sender;

        vm.startBroadcast();
        Helm helm = new Helm();
        ManualMetricOracle oracle = new ManualMetricOracle(deployer);
        vm.stopBroadcast();

        console.log("=== Helm v0 deployment ===");
        console.log("Chain ID:           ", block.chainid);
        console.log("Helm:               ", address(helm));
        console.log("ManualMetricOracle: ", address(oracle));
        console.log("Oracle reporter:    ", deployer);
    }
}
