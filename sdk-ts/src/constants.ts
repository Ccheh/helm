import type { Hex } from "./types.js";

export interface ArcChain {
  chainId: number;
  rpc: string;
  explorer: string;
}

export const ARC_TESTNET: ArcChain = {
  chainId: 5042002,
  rpc: "https://rpc.testnet.arc.network",
  explorer: "https://testnet.arcscan.app",
};

/** Canonical Helm v0 deployments on Arc Testnet. */
export const HELM_ARC_TESTNET = {
  helm: "0x47e6d5669d302c8ed6b32189820f36c172a02691" as Hex,
  manualOracle: "0xee573c409c2847bbfb564283afac3338e1e6356c" as Hex,
  /**
   * Adapter that exposes a CrucibleMarketV6 market's `scoreBps` as an
   * IMetricOracle for Helm. Pointed at CrucibleMarketV6 at
   * 0x6535a3CbB4235746B732aB5d55c6b0988F381A20 on Arc Testnet.
   * Deploy tx: 0xdc1d202178623a9eb4b6a080144f7cfc9bef6548dab99606ee66aadadf0d2b22
   */
  crucibleMetricOracle: "0x8d7efaacbf2e944e459801f891577b40fa6124c4" as Hex,
} as const;

/** Helm.sol enum + branch/side constants — mirror of on-chain values. */
export const Status = { None: 0, Open: 1, Decided: 2, Resolved: 3 } as const;
export type StatusName = keyof typeof Status;

/** branch: 0 = X (the proposed policy), 1 = NOT_X */
export const Branch = { X: 0, NOT_X: 1 } as const;
export type BranchValue = typeof Branch[keyof typeof Branch];

/** side: 0 = YES (metric > threshold), 1 = NO */
export const Side = { YES: 0, NO: 1 } as const;
export type SideValue = typeof Side[keyof typeof Side];

export const HELM_ABI = [
  {
    type: "function", name: "proposeIssue", stateMutability: "nonpayable",
    inputs: [
      { name: "metricOracle", type: "address" },
      { name: "metricKey", type: "bytes32" },
      { name: "threshold", type: "uint256" },
      { name: "decideAt", type: "uint64" },
      { name: "resolveAt", type: "uint64" },
      { name: "defaultDecision", type: "uint8" },
    ],
    outputs: [{ name: "issueId", type: "bytes32" }],
  },
  {
    type: "function", name: "bet", stateMutability: "payable",
    inputs: [
      { name: "issueId", type: "bytes32" },
      { name: "branch", type: "uint8" },
      { name: "side", type: "uint8" },
    ],
    outputs: [],
  },
  {
    type: "function", name: "decide", stateMutability: "nonpayable",
    inputs: [{ name: "issueId", type: "bytes32" }], outputs: [],
  },
  {
    type: "function", name: "resolve", stateMutability: "nonpayable",
    inputs: [
      { name: "issueId", type: "bytes32" },
      { name: "oracleData", type: "bytes" },
    ], outputs: [],
  },
  {
    type: "function", name: "claim", stateMutability: "nonpayable",
    inputs: [{ name: "issueId", type: "bytes32" }],
    outputs: [{ name: "payout", type: "uint256" }],
  },
  {
    type: "function", name: "issues", stateMutability: "view",
    inputs: [{ type: "bytes32" }],
    outputs: [
      { name: "proposer", type: "address" },
      { name: "metricOracle", type: "address" },
      { name: "metricKey", type: "bytes32" },
      { name: "threshold", type: "uint256" },
      { name: "decideAt", type: "uint64" },
      { name: "resolveAt", type: "uint64" },
      { name: "defaultDecision", type: "uint8" },
      { name: "status", type: "uint8" },
      { name: "chosenBranch", type: "uint8" },
      { name: "metricMet", type: "bool" },
      { name: "metricValue", type: "uint256" },
    ],
  },
  {
    type: "function", name: "pools", stateMutability: "view",
    inputs: [{ type: "bytes32" }],
    outputs: [
      { name: "xYes", type: "uint256" },
      { name: "xNo", type: "uint256" },
      { name: "notxYes", type: "uint256" },
      { name: "notxNo", type: "uint256" },
    ],
  },
  {
    type: "function", name: "prices", stateMutability: "view",
    inputs: [{ type: "bytes32" }],
    outputs: [
      { name: "pX", type: "uint256" },
      { name: "pNotX", type: "uint256" },
    ],
  },
  {
    type: "function", name: "userBet", stateMutability: "view",
    inputs: [
      { type: "bytes32" }, { type: "uint8" }, { type: "uint8" }, { type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function", name: "issueCount", stateMutability: "view",
    inputs: [], outputs: [{ type: "uint256" }],
  },
  { type: "function", name: "MIN_BET", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },

  // events (for log decoding)
  {
    type: "event", name: "IssueProposed",
    inputs: [
      { indexed: true, name: "issueId", type: "bytes32" },
      { indexed: true, name: "proposer", type: "address" },
      { indexed: true, name: "metricOracle", type: "address" },
      { indexed: false, name: "metricKey", type: "bytes32" },
      { indexed: false, name: "threshold", type: "uint256" },
      { indexed: false, name: "decideAt", type: "uint64" },
      { indexed: false, name: "resolveAt", type: "uint64" },
      { indexed: false, name: "defaultDecision", type: "uint8" },
    ],
  },
  {
    type: "event", name: "BetPlaced",
    inputs: [
      { indexed: true, name: "issueId", type: "bytes32" },
      { indexed: true, name: "bettor", type: "address" },
      { indexed: false, name: "branch", type: "uint8" },
      { indexed: false, name: "side", type: "uint8" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "newPoolTotal", type: "uint256" },
    ],
  },
  {
    type: "event", name: "IssueDecided",
    inputs: [
      { indexed: true, name: "issueId", type: "bytes32" },
      { indexed: false, name: "chosenBranch", type: "uint8" },
      { indexed: false, name: "pX_yes_x_totalNotX", type: "uint256" },
      { indexed: false, name: "pNotX_yes_x_totalX", type: "uint256" },
    ],
  },
  {
    type: "event", name: "IssueResolved",
    inputs: [
      { indexed: true, name: "issueId", type: "bytes32" },
      { indexed: false, name: "chosenBranch", type: "uint8" },
      { indexed: false, name: "metricMet", type: "bool" },
      { indexed: false, name: "metricValue", type: "uint256" },
    ],
  },
  {
    type: "event", name: "Claimed",
    inputs: [
      { indexed: true, name: "issueId", type: "bytes32" },
      { indexed: true, name: "user", type: "address" },
      { indexed: false, name: "amount", type: "uint256" },
    ],
  },
] as const;

export const MANUAL_ORACLE_ABI = [
  {
    type: "function", name: "reportMetric", stateMutability: "nonpayable",
    inputs: [
      { name: "issueId", type: "bytes32" },
      { name: "value", type: "uint256" },
    ], outputs: [],
  },
  {
    type: "function", name: "isReady", stateMutability: "view",
    inputs: [{ name: "issueId", type: "bytes32" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function", name: "getMetric", stateMutability: "view",
    inputs: [
      { name: "issueId", type: "bytes32" },
      { name: "", type: "bytes" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function", name: "reporter", stateMutability: "view",
    inputs: [], outputs: [{ type: "address" }],
  },
] as const;
