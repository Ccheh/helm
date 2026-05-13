export type Hex = `0x${string}`;

export interface IssueParams {
  metricOracle: Hex;
  metricKey: Hex;          // bytes32 — opaque, derived per use case
  threshold: bigint;
  decideAt: bigint;        // unix seconds
  resolveAt: bigint;       // unix seconds
  defaultDecision: 0 | 1;  // 0 = X, 1 = NOT_X
}

export interface IssueState {
  proposer: Hex;
  metricOracle: Hex;
  metricKey: Hex;
  threshold: bigint;
  decideAt: bigint;
  resolveAt: bigint;
  defaultDecision: number;
  status: number;          // 0=None 1=Open 2=Decided 3=Resolved
  chosenBranch: number;    // 0=X 1=NOT_X
  metricMet: boolean;
  metricValue: bigint;
}

export interface PoolSnapshot {
  xYes: bigint;
  xNo: bigint;
  notxYes: bigint;
  notxNo: bigint;
}

export interface PriceSnapshot {
  pX: bigint;     // P(YES | X), scaled 1e18; 0 if no X bets
  pNotX: bigint;  // P(YES | NOT_X), scaled 1e18; 0 if no NOT_X bets
}
