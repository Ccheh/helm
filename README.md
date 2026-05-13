# Helm

> **Futarchy for autonomous agent coordination.** Group decisions made by comparing prediction-market prices on conditional outcomes, with the rejected branch's bets refunded. An on-chain implementation of Robin Hanson's futarchy mechanism, targeted at the audience that can actually use it: software agents on Arc.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-50%20forge%20%2B%2019%20SDK-success)](#)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.28-blue)](contracts/foundry.toml)
[![Arc](https://img.shields.io/badge/Arc%20Testnet-v0%20live-blue)](https://testnet.arcscan.app/address/0x47e6d5669d302c8ed6b32189820f36c172a02691)

### Deployed on Arc Testnet

| Contract | Address | Deploy tx |
|---|---|---|
| **Helm** (core futarchy contract) | [`0x47e6d5669d302c8ed6b32189820f36c172a02691`](https://testnet.arcscan.app/address/0x47e6d5669d302c8ed6b32189820f36c172a02691) | [`0x448362fd...`](https://testnet.arcscan.app/tx/0x448362fd7bb1600a9bd3fa588dadd7ca3ff0d002f329aba8be0edbea7705c1ed) |
| **ManualMetricOracle** (v0 default) | [`0xee573c409c2847bbfb564283afac3338e1e6356c`](https://testnet.arcscan.app/address/0xee573c409c2847bbfb564283afac3338e1e6356c) | [`0xbd2863d3...`](https://testnet.arcscan.app/tx/0xbd2863d31b074ae2cae2c858a1d12f1403603a7807be2f0196edc218a198dac0) |
| **CrucibleMetricOracle** (Crucible v0.6 adapter) | [`0x8d7efaacbf2e944e459801f891577b40fa6124c4`](https://testnet.arcscan.app/address/0x8d7efaacbf2e944e459801f891577b40fa6124c4) | [`0xdc1d2021...`](https://testnet.arcscan.app/tx/0xdc1d202178623a9eb4b6a080144f7cfc9bef6548dab99606ee66aadadf0d2b22) |

### Live lifecycle on chain

A full `propose → bet × 4 → decide → oracleReport → resolve → claim × 2`
sequence has been executed on Arc Testnet through the
[`@helm/sdk`](sdk-ts/) TypeScript SDK. Issue id:
`0xc003ec854ac99d1054541f6160568b13bff6f4e443bbaa25422ff3392eb29d46`.

| Step | tx |
|---|---|
| `proposeIssue` (threshold=1000, decideAt=+4min, resolveAt=+6min) | [`0xc4b18a4f...`](https://testnet.arcscan.app/tx/0xc4b18a4fec6a782bdeac580d0f52a368b858f7ea52bbc05b13d0305a476ad15e) |
| 4 parimutuel bets (X-YES, X-NO, NOT_X-YES, NOT_X-NO) | [`0x609acba1...`](https://testnet.arcscan.app/tx/0x609acba16d6fb2b87b5d06359b52e48ea3e4a1d9b909eb6114c0543436329693) [`0x6e3f5b36...`](https://testnet.arcscan.app/tx/0x6e3f5b361d3ef19fb8056d805121916ca240876b2a55b52726d5f6ae509aae90) [`0x71ec5dea...`](https://testnet.arcscan.app/tx/0x71ec5dea0cbbee1b9bc3c1120195057be53f69ad40e754972b5bbe3dbbed3c44) [`0x11942c4b...`](https://testnet.arcscan.app/tx/0x11942c4b9240f96f93a478a16619ed90eee23a05a8456c844c8f5c132f3faef7) |
| `decide` (chose X — P(YES\|X)=0.60 > P(YES\|NOT_X)=0.33) | [`0xda16f5eb...`](https://testnet.arcscan.app/tx/0xda16f5ebf9670b88b7275985e85167c7f6cf93073a53c4dfdf62db010bb0564f) |
| `ManualMetricOracle.reportMetric(2000)` | [`0xb40e98fa...`](https://testnet.arcscan.app/tx/0xb40e98fa6fa791bd30ab956e909f62c1a0250a1bea78c71bb0112d0c2f0b398b) |
| `resolve` (metric=2000 > threshold=1000 → YES wins) | [`0xba4b89c6...`](https://testnet.arcscan.app/tx/0xba4b89c62d152468e2715e40182bc605e58293ef0ef268ca96c7258d8779de67) |
| PROPOSER `claim` (X-YES winner: principal + X-NO pool + NOT_X-YES refund = 0.003 USDC) | [`0x7b758c13...`](https://testnet.arcscan.app/tx/0x7b758c1362318a19b6c68d32c62572fe3c5b7c4a4bf2f8ead5bdff91592a00f5) |
| COUNTER `claim` (NOT_X-NO refund = 0.001 USDC; X-NO lost) | [`0xab76c9b4...`](https://testnet.arcscan.app/tx/0xab76c9b4bb9d7b30b3a86244088b7cc9b8d3b15608df084a1c1093d5eecbd8e5) |

Total bets locked: 0.004 USDC. Total claimed: 0.004 USDC (3+1). Conservation
verified on chain. This is the first full futarchy lifecycle ever executed
end-to-end on Arc.

> **Read this first.** Helm is a research-grade reference implementation. There are no production adopters yet — there are no production agent DAOs to adopt it. The mechanism design is the contribution; the bet is that the audience materializes. If you came here expecting a turnkey decision system for your DAO, **this isn't that today**. Honest limits at the bottom.

---

## The thesis in one paragraph

Futarchy — *"vote on values, bet on beliefs"* — was proposed by Robin Hanson. The mechanism is theoretically attractive: instead of voters expressing preferences, traders bet on the conditional consequences of each policy, and the policy with the higher implied expected outcome wins. Bets on the rejected branch are refunded. The mechanism creates aligned incentives: bet truthfully, get paid only if your bet was informative.

It has never been deployed at scale anywhere, for two reasons:
1. **Humans bet emotionally.** People get attached to predictions, anchor on their priors, and confuse betting with advocacy. Futarchy needs cold rational arbitrage.
2. **Human bet sizes are too coarse.** Fine-grained signal requires many small bets. On Ethereum mainnet, $0.10 swap fees price out the sub-cent stakes that would let real futarchy work.

**Agents are the audience this primitive has been waiting for.** They have no ego. They have no loss aversion. They can place a thousand $0.0001 bets in seconds. Arc's USDC-native gas makes those bets economical. **Helm is the bet that decades after the mechanism was first proposed, the conditions for futarchy to actually work are finally here, and that the natural participants are autonomous agents, not humans.**

---

## How it works

Each issue has 4 parimutuel pools:

```
              YES (metric > threshold)    NO (metric ≤ threshold)
Branch X      pool[X][YES]               pool[X][NO]
Branch NOT_X  pool[NOT_X][YES]           pool[NOT_X][NO]
```

### Lifecycle

```
None  →  Open  →  Decided  →  Resolved
        propose  decide()    resolve(metric)
                 at decideAt at resolveAt
```

**Propose**. Anyone (humans, smart contracts, agents) calls `proposeIssue(metricOracle, metricKey, threshold, decideAt, resolveAt, defaultDecision)`. The contract records the parameters; bets open immediately.

**Bet**. Anyone calls `bet(issueId, branch, side)` with USDC as `msg.value`. Funds flow into `pool[branch][side]`. Betting closes at `decideAt`.

**Decide**. At `decideAt`, anyone calls `decide(issueId)`. The contract compares conditional YES prices:

```
p_X     = pool[X][YES]     / (pool[X][YES] + pool[X][NO])
p_NOT_X = pool[NOT_X][YES] / (pool[NOT_X][YES] + pool[NOT_X][NO])
chosen  = X if p_X > p_NOT_X else NOT_X
```

(Comparison is done by cross-multiplication; no division on chain.)

The rejected branch's bets become refundable. The chosen branch remains in play until resolution.

**Resolve**. At `resolveAt`, anyone calls `resolve(issueId, oracleData)`. The contract queries `IMetricOracle.getMetric(issueId, oracleData)`, compares the value against the threshold, and marks the issue resolved.

**Claim**. Any participant calls `claim(issueId)`. The contract:
- Refunds all of the user's bets on the rejected branch (full principal).
- If resolved, pays out the user's chosen-branch winnings:
  - If `metric > threshold`: YES pool wins. Each YES bettor gets back their principal plus a pro-rata share of the NO pool.
  - Otherwise: NO pool wins symmetrically.

Settlement is **parimutuel**. There is no AMM, no LMSR, no liquidity provider. Winners split losers' stakes pro-rata.

### A concrete example

> An agent DAO with 50 trading agents must decide: should we adopt strategy X?
>
> They define the metric: *portfolio value after 30 days*. Threshold: $1000.
> They post the issue with `decideAt = now + 24h`, `resolveAt = now + 31 days`.
>
> Day 0: agents bet. Some bet `X-YES` (they think X leads to portfolio > $1000). Some bet `X-NO`. Some bet on the `NOT_X` branch.
>
> Day 1, `decideAt`: `p(YES | X) = 0.7`, `p(YES | NOT_X) = 0.4`. Chosen branch: X. The agent DAO adopts strategy X. NOT_X bettors get their stakes refunded.
>
> Day 31, `resolveAt`: portfolio value is $1500. YES wins on X. YES bettors split the X-NO pool pro-rata.

---

## Architecture

```
┌────────────────────────────────────────────┐
│  Application: agent DAO governance         │
├────────────────────────────────────────────┤
│  ★ Helm — futarchy decision protocol       │ ← this repo
│  • per-issue 4-pool parimutuel betting     │
│  • on-chain price-comparison decision rule │
│  • rejected-branch refunds                 │
│  • parimutuel settlement                   │
├────────────────────────────────────────────┤
│  IMetricOracle (pluggable)                 │
│  • ManualMetricOracle (v0, test)           │
│  • Chainlink/Pyth adapters (v0.2)          │
│  • Crucible TestcaseResolverV5 adapter     │
│    (uses validator network for resolution) │
├────────────────────────────────────────────┤
│  Arc — USDC as native gas, sub-cent fees   │
└────────────────────────────────────────────┘
```

Helm composes with [Cadence](https://github.com/Ccheh/arc402) (the payment-layer protocol that uses the same Arc-native-USDC pattern) and [Crucible](https://github.com/Ccheh/crucible) (the quality-conditional settlement protocol whose validator network can act as a Helm `IMetricOracle`).

---

## Reproducing the v0 tests

```sh
git clone https://github.com/Ccheh/helm
cd helm/contracts
forge install
forge test
```

Expected output: `31 passed; 0 failed; 0 skipped` across:
- `propose` happy path + 3 revert cases
- `bet` happy path + 4 revert cases + accumulation
- `decide` for 7 distinct pool configurations + revert cases
- `resolve` happy paths + readiness/timing reverts
- `claim` for rejected-branch refunds, chosen-branch winners (YES and NO), pro-rata payout to multiple winners, partial-claim idempotency, no-claim revert
- End-to-end lifecycle test mirroring the example above

---

## Repository layout

```
contracts/src/
├── Helm.sol                          — core futarchy contract
├── interfaces/IMetricOracle.sol      — pluggable oracle interface
└── oracles/
    ├── ManualMetricOracle.sol        — v0 test oracle (NOT for production)
    └── CrucibleMetricOracle.sol      — adapter exposing a CrucibleMarketV6
                                        scoreBps as an IMetricOracle metric

contracts/test/
├── Helm.t.sol                        — 31 forge tests
└── CrucibleMetricOracle.t.sol        — 19 forge tests
                                        (incl. end-to-end Helm+adapter integration)

sdk-ts/
├── src/
│   ├── HelmClient.ts                 — lifecycle client (propose/bet/decide/resolve/claim)
│   ├── OracleClient.ts               — ManualMetricOracle reporter client
│   ├── constants.ts                  — ABI + deployed addresses
│   └── utils.ts                      — deriveIssueId, metricKeyOf
├── examples/
│   ├── full-lifecycle.ts             — the script that ran the on-chain lifecycle above
│   └── retry-counter-claim.ts        — utility for the testnet mempool-full edge case
└── test/                             — 19 vitest unit tests
```

SDK at v0.0.1 (TypeScript). Verified end-to-end on Arc Testnet via the
lifecycle txs in the table above.

---

## Honest limits

If you are evaluating Helm for any actual integration, read this carefully.

- **No production adopters.** No agent DAO is using Helm today, on any chain. The number of mature autonomous agent DAOs in May 2026 is roughly zero. **The bet is that the audience materializes** — and it might not.
- **Pre-audit, pre-mainnet.** 50 forge tests pass + 19 SDK vitest tests + [`audits/slither-report.md`](audits/slither-report.md) reports no high or medium severity findings. No independent external audit has happened. Treat as research code.
- **Manual oracle in v0 (but Crucible adapter shipped).** The shipped `ManualMetricOracle` is trivially trusted (a reporter address sets values without challenge). `CrucibleMetricOracle` is the production-realistic adapter — it lets Helm consume Crucible's stake-weighted validator-network score as the metric. Deployed and tested end-to-end (forge: `test_endToEnd_helmResolvesFromCrucibleScore`).
- **Decision attack surface.** A coordinated whale can bet large amounts on the favored branch in either direction near `decideAt`. There is no commit-reveal phase, no slippage protection, no impermanent fairness guarantee. v0.2 may borrow Crucible's commit-reveal pattern if a real attack vector emerges in practice.
- **Stuck-oracle risk.** If the chosen `IMetricOracle` never reports `isReady = true`, the issue is stuck in `Decided` indefinitely. Bets on the chosen branch are locked. v0.2 should add a force-resolve-default fallback (mirroring Crucible v0.6's `forceResolveStale`).
- **Parimutuel math edge cases.** A chosen-branch loser pool larger than the winner pool can produce extreme payouts (a winning bet can multiply many times its size). This is intended behavior for parimutuel markets but can feel unintuitive.
- **Arc specificity is loose.** Helm could run on any EVM chain. Arc is chosen because USDC-native-gas + sub-cent settlement enables the dense fine-grained betting that distinguishes agent futarchy from human futarchy. On a chain where each bet costs $0.10 in gas, Helm is uninteresting.
- **Default decision is a soft attack surface.** When pools are empty or tied, the issue resolves to the proposer-specified default. A proposer who controls timing could exploit this. Use Helm only with proposers you trust to set sane defaults.
- **No protocol fees.** Helm takes 0% in v0. If this becomes a real protocol, fee economics will need design. None of that is built.

---

## Why this protocol, why now, and where it goes

The author ([Zen Chen](https://github.com/Ccheh)) has been interested in prediction-market mechanism design for a while. After shipping [Cadence](https://github.com/Ccheh/arc402) (streaming USDC payments middleware — the same architectural slot Circle's official Nanopayments occupies) and [Crucible](https://github.com/Ccheh/crucible) (a stake-weighted Schelling consensus for AI output quality), the lesson learned from both was: **the most novel mechanism designs in this space are the ones the incumbents haven't shipped because their DNA doesn't include mechanism design.** Circle has payment DNA, not mechanism-design DNA. The prediction-market incumbents have mechanism-design DNA but focus on human-facing markets, not agent-coordination markets.

Helm is the bet that there's a third position the incumbents will leave open: **the mechanism-design layer for autonomous agent groups**. It might not be a market today. It probably won't be a market in 6 months. It might be a real market in 24 months, when ten thousand small agent DAOs need to make coordinated decisions and tokenized voting is obviously insufficient.

If that future arrives, Helm is the reference implementation built ahead of it. If it doesn't, Helm is a clean piece of mechanism-design portfolio: a 30-year-old idea that's never been deployed, implemented on the first chain where it could actually work.

---

## License

[MIT](LICENSE)

## Author

[Zen Chen](https://github.com/Ccheh) — MSc Data Science (Sheffield). Built on Arc.
