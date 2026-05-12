# Helm

> **Futarchy for autonomous agent coordination.** Group decisions made by comparing prediction-market prices on conditional outcomes, with the rejected branch's bets refunded. An on-chain implementation of Robin Hanson's 1996 mechanism, targeted at the audience that can actually use it: software agents on Arc.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-31%2F31%20passing-success)](#)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.28-blue)](contracts/foundry.toml)
[![Arc](https://img.shields.io/badge/Arc%20Testnet-v0%20live-blue)](https://testnet.arcscan.app/address/0x47e6d5669d302c8ed6b32189820f36c172a02691)

### v0 on Arc Testnet

| Contract | Address | Deploy tx |
|---|---|---|
| **Helm** | [`0x47e6d5669d302c8ed6b32189820f36c172a02691`](https://testnet.arcscan.app/address/0x47e6d5669d302c8ed6b32189820f36c172a02691) | [`0x448362fd...`](https://testnet.arcscan.app/tx/0x448362fd7bb1600a9bd3fa588dadd7ca3ff0d002f329aba8be0edbea7705c1ed) |
| **ManualMetricOracle** | [`0xee573c409c2847bbfb564283afac3338e1e6356c`](https://testnet.arcscan.app/address/0xee573c409c2847bbfb564283afac3338e1e6356c) | [`0xbd2863d3...`](https://testnet.arcscan.app/tx/0xbd2863d31b074ae2cae2c858a1d12f1403603a7807be2f0196edc218a198dac0) |

Deployed gas: ~1.6M (~0.032 USDC at 20 gwei).

> **Read this first.** Helm is a research-grade reference implementation. There are no production adopters yet — there are no production agent DAOs to adopt it. The mechanism design is the contribution; the bet is that the audience materializes. If you came here expecting a turnkey decision system for your DAO, **this isn't that today**. Honest limits at the bottom.

---

## The thesis in one paragraph

Futarchy — *"vote on values, bet on beliefs"* — was proposed by Robin Hanson in 1996. The mechanism is theoretically attractive: instead of voters expressing preferences, traders bet on the conditional consequences of each policy, and the policy with the higher implied expected outcome wins. Bets on the rejected branch are refunded. The mechanism creates aligned incentives: bet truthfully, get paid only if your bet was informative.

It has never been deployed at scale anywhere, for two reasons:
1. **Humans bet emotionally.** People get attached to predictions, anchor on their priors, and confuse betting with advocacy. Futarchy needs cold rational arbitrage.
2. **Human bet sizes are too coarse.** Fine-grained signal requires many small bets. On Ethereum mainnet, $0.10 swap fees price out the sub-cent stakes that would let real futarchy work.

**Agents are the audience this primitive has been waiting for.** They have no ego. They have no loss aversion. They can place a thousand $0.0001 bets in seconds. Arc's USDC-native gas makes those bets economical. **Helm is the bet that 30 years after Hanson, the conditions for futarchy to actually work are finally here, and that the natural participants are autonomous agents, not humans.**

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
├── Helm.sol                       — core futarchy contract
├── interfaces/IMetricOracle.sol   — pluggable oracle interface
└── oracles/ManualMetricOracle.sol — v0 test oracle (NOT for production)

contracts/test/
└── Helm.t.sol                     — 31 forge tests
```

No SDK yet. SDK comes after the first real deploy + a first integrator (if either ever happens).

---

## Honest limits

If you are evaluating Helm for any actual integration, read this carefully.

- **No production adopters.** No agent DAO is using Helm today, on any chain. The number of mature autonomous agent DAOs in May 2026 is roughly zero. **The bet is that the audience materializes** — and it might not.
- **Pre-audit, pre-mainnet.** 31 forge tests pass. No independent security review has happened. Treat as research code.
- **No real on-chain lifecycle yet, only deployment.** v0 is deployed to Arc Testnet (addresses + deploy txs above) but **no full propose → bet → decide → resolve → claim cycle has been run on a live chain**. The 31 forge tests cover the mechanism comprehensively, but real-chain end-to-end is the next milestone.
- **Manual oracle in v0.** The shipped `ManualMetricOracle` is trivially trusted (a reporter address sets values without challenge). Real deployments need a validator-network oracle — most realistic adapter is a thin wrapper over Crucible's `TestcaseResolverV5`. That's v0.2 work.
- **No SDK yet.** Wallet integration is raw `viem` / `cast` calls. SDK is deferred until there's evidence anyone wants one.
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
