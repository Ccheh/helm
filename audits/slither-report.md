# Helm — Slither static analysis report

> **What this is**: self-run static analysis with the public Slither tool.
> **What this isn't**: a formal independent audit. No external audit firm
> has reviewed Helm. Treat the contract as research-grade pending audit.

**Tool**: [slither-analyzer](https://github.com/crytic/slither) v0.11.5
**Solidity**: 0.8.28
**Scope**: `contracts/src/` (Helm.sol, ManualMetricOracle.sol, interfaces/)
**Date**: 2026-05-13
**Total detectors run**: 101
**Total findings**: 5 (all informational severity)

## Findings summary

| # | Detector | Location | Severity | Action |
|---|---|---|---|---|
| 1 | `timestamp` | `proposeIssue` line 173 | Informational | **No fix needed** — timing window comparisons are intentional |
| 2 | `timestamp` | `bet` line 220 | Informational | **No fix needed** — same |
| 3 | `timestamp` | `decide` line 239 | Informational | **No fix needed** — same |
| 4 | `timestamp` | `resolve` line 281 | Informational | **No fix needed** — same |
| 5 | `low-level-calls` | `claim` line 341 | Informational | **No fix needed** — required for native USDC transfer on Arc |

## Detail

### Findings 1–4: `block.timestamp` comparisons

Helm's futarchy mechanism requires four distinct time windows
(`decideAt`, `resolveAt`, `block.timestamp < x`, `block.timestamp >= x`).
Slither flags any use of `block.timestamp` for comparisons because miners
can manipulate timestamps by up to ~15 seconds. For Helm specifically:

- The smallest meaningful interval is `resolveAt - decideAt`, which the
  contract requires to be strictly positive (line 173). Real deployments
  would set this to minutes-to-hours.
- A 15-second miner manipulation is dwarfed by the protocol's natural
  granularity. No exploit possible.

This is the standard, accepted pattern for any contract with timed phases.

### Finding 5: Low-level call in `claim()`

```solidity
(bool ok,) = msg.sender.call{value: payout}("");
if (!ok) revert TransferFailed();
```

On Arc, USDC is the native gas asset — so transferring USDC means a
native-value `call`. Using `transfer` is not recommended (2300-gas limit
is a [known anti-pattern](https://consensys.io/diligence/blog/2019/09/stop-using-soliditys-transfer-now/)),
and high-level `payable(addr).send()` has the same issue. The pattern shown
is the OpenZeppelin-recommended approach.

`claim()` is protected by `ReentrancyGuard.nonReentrant`. The call to the
recipient happens **after** all storage updates (checks-effects-interactions).
No reentrancy or unexpected-state risk.

## What Slither did NOT flag (independent verification)

- **Reentrancy**: zero matches.
- **Arithmetic overflow / underflow**: zero matches (Solidity 0.8.28 native overflow checks + no `unchecked` arithmetic except the safe `issueCount++`).
- **Tx.origin authorization**: zero matches (msg.sender used throughout).
- **Storage layout collisions**: no upgrade proxy, so N/A.
- **Unsafe delegatecall**: zero matches (no delegatecalls).
- **Unprotected selfdestruct**: zero matches (no selfdestruct).
- **Unbounded loops**: zero matches.

## How to reproduce

```sh
cd contracts
pip install slither-analyzer  # tested with 0.11.5
solc-select install 0.8.28
solc-select use 0.8.28
slither src/ --solc-remaps "openzeppelin-contracts/=lib/openzeppelin-contracts/" --filter-paths "lib|test"
```

## Honest caveats

Slither only catches **automatable** issues. It misses:
- Economic incentive analysis (parimutuel payout edge cases — covered by 31 forge tests including `test_claim_chosenBranch_*` and `test_claim_proRataBetweenMultipleWinners`)
- Game-theoretic attacks (whale buying near `decideAt` — acknowledged in README's Honest Limits)
- Cross-contract invariants (e.g., oracle trust — `ManualMetricOracle` is trivially trusted, also documented in README)

A real audit by an audit firm (Trail of Bits, ChainSecurity, OpenZeppelin, etc.)
would cost $10K-$50K and take 2-6 weeks. This is not a substitute. It is the
best self-served evidence we can offer pre-funding.
