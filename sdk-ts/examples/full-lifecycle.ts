/**
 * End-to-end Helm v0 lifecycle demo on Arc Testnet, driven entirely through
 * @helm/sdk. Two-wallet scenario:
 *
 *   - PROPOSER (MAIN_PK) — proposes the issue, bets on X-YES, bets a small
 *     hedge on NOT_X-YES, reports the metric (as oracle reporter), claims.
 *   - COUNTER (SERVICE_PK) — bets against on X-NO and NOT_X-NO, claims its
 *     rejected-branch refund.
 *
 * Issue: "Should agent collective adopt strategy X?"
 *   Metric:    `portfolio_value` (manual oracle)
 *   Threshold: 1000  (YES wins if reported value > 1000)
 *   Default:   X     (if pools tie/empty, X is chosen)
 *
 * Expected outcome:
 *   - X-YES (0.001) > X-NO (0.001)? Equal. Cross-multiplication on equality
 *     defaults to `defaultDecision = X` per the contract. Chosen branch: X.
 *   - We give X a slight edge: PROPOSER bets 0.0015 on X-YES, COUNTER bets
 *     0.001 on X-NO. p_X = 0.6.
 *   - PROPOSER hedges 0.0005 on NOT_X-YES; COUNTER bets 0.001 on NOT_X-NO.
 *     p_NOT_X = 0.333.
 *   - 0.6 > 0.333 → X chosen.
 *   - Oracle reports value=2000 > threshold=1000 → metricMet=true → X-YES wins.
 *   - PROPOSER (sole X-YES bettor) wins X-NO pool (0.001) and gets back NOT_X-YES (0.0005).
 *   - COUNTER gets back NOT_X-NO refund (0.001). X-NO bet (0.001) was lost.
 *
 * Total bets locked: 0.0015 + 0.0005 + 0.001 + 0.001 = 0.004 USDC
 * Total claimed:     PROPOSER 0.003 + COUNTER 0.001 = 0.004 USDC  (conservation OK)
 *
 * Bet sizes are tiny (sub-cent) — total exposure ~0.004 USDC + ~10 tx of gas.
 * Picked deliberately to demonstrate the mechanism without burning testnet USDC.
 *
 * Timing:
 *   decideAt   = now + 4 min
 *   resolveAt  = now + 6 min
 * Script wall-clock: ~7-8 min.
 */

import { parseEther, formatEther } from "viem";
import {
  HelmClient,
  OracleClient,
  HELM_ARC_TESTNET,
  ARC_TESTNET,
  Status,
  Branch,
  metricKeyOf,
  type Hex,
} from "../src/index.js";

// ---------- env ----------
const ENV_PATH = "D:\\桌面\\arc\\.env";
process.loadEnvFile(ENV_PATH);

const MAIN_PK = process.env.PRIVATE_KEY as Hex;
const SERVICE_PK = process.env.SERVICE_PRIVATE_KEY as Hex;
if (!MAIN_PK || !SERVICE_PK) throw new Error("Missing PRIVATE_KEY / SERVICE_PRIVATE_KEY in .env");

const HELM = HELM_ARC_TESTNET.helm;
const ORACLE = HELM_ARC_TESTNET.manualOracle;
const EXPLORER = ARC_TESTNET.explorer;

// ---------- clients ----------
const proposer = new HelmClient({ privateKey: MAIN_PK, helmAddress: HELM });
const counter  = new HelmClient({ privateKey: SERVICE_PK, helmAddress: HELM });
const oracle   = new OracleClient({ privateKey: MAIN_PK, oracleAddress: ORACLE });

console.log(`PROPOSER : ${proposer.address}  (also oracle reporter)`);
console.log(`COUNTER  : ${counter.address}\n`);

// ---------- step 1: propose ----------
const now = Math.floor(Date.now() / 1000);
const decideAt = BigInt(now + 4 * 60);   // +4 min
const resolveAt = BigInt(now + 6 * 60);  // +6 min

console.log(`Step 1: PROPOSER proposes issue (decideAt=+4min, resolveAt=+6min)`);
const { txHash: proposeTx, issueId } = await proposer.proposeIssue({
  metricOracle: ORACLE,
  metricKey: metricKeyOf("portfolio_value_v1"),
  threshold: 1000n,
  decideAt,
  resolveAt,
  defaultDecision: Branch.X,
});
console.log(`  propose tx: ${EXPLORER}/tx/${proposeTx}`);
console.log(`  issueId:    ${issueId}\n`);

// ---------- step 2: betting ----------
console.log(`Step 2: 4 parimutuel bets`);

console.log(`  PROPOSER  bets 0.0015 USDC on X-YES   (bullish on X)`);
const b1 = await proposer.betXYes(issueId, parseEther("0.0015"));
console.log(`    ${EXPLORER}/tx/${b1}`);

console.log(`  COUNTER   bets 0.001  USDC on X-NO    (bearish on X)`);
const b2 = await counter.betXNo(issueId, parseEther("0.001"));
console.log(`    ${EXPLORER}/tx/${b2}`);

console.log(`  PROPOSER  bets 0.0005 USDC on NOT_X-YES (small hedge)`);
const b3 = await proposer.betNotXYes(issueId, parseEther("0.0005"));
console.log(`    ${EXPLORER}/tx/${b3}`);

console.log(`  COUNTER   bets 0.001  USDC on NOT_X-NO`);
const b4 = await counter.betNotXNo(issueId, parseEther("0.001"));
console.log(`    ${EXPLORER}/tx/${b4}\n`);

const poolsAfterBet = await proposer.getPools(issueId);
const pricesAfterBet = await proposer.getPrices(issueId);
console.log(`  Pools: X-YES=${formatEther(poolsAfterBet.xYes)}  X-NO=${formatEther(poolsAfterBet.xNo)}`);
console.log(`         NOT_X-YES=${formatEther(poolsAfterBet.notxYes)}  NOT_X-NO=${formatEther(poolsAfterBet.notxNo)}`);
console.log(`  P(YES|X)=${(Number(pricesAfterBet.pX) / 1e18).toFixed(3)}  P(YES|NOT_X)=${(Number(pricesAfterBet.pNotX) / 1e18).toFixed(3)}\n`);

// ---------- step 3: wait for decideAt ----------
const waitForDecide = Number(decideAt) - Math.floor(Date.now() / 1000) + 5;  // +5s buffer
console.log(`Step 3: waiting ${waitForDecide}s until decideAt...`);
await new Promise(r => setTimeout(r, waitForDecide * 1000));
console.log(`  done.\n`);

console.log(`Step 4: anyone calls decide(). PROPOSER will call it here.`);
const decideTx = await proposer.decide(issueId);
console.log(`  decide tx: ${EXPLORER}/tx/${decideTx}`);
const issueAfterDecide = await proposer.getIssue(issueId);
console.log(`  status:       ${issueAfterDecide.status} (Decided)`);
console.log(`  chosenBranch: ${issueAfterDecide.chosenBranch} (${issueAfterDecide.chosenBranch === Branch.X ? "X" : "NOT_X"})\n`);

if (issueAfterDecide.chosenBranch !== Branch.X) {
  console.log(`  WARNING: NOT_X was chosen — does the bet distribution still demo the lifecycle?`);
  console.log(`  Continuing anyway...\n`);
}

// ---------- step 5: oracle reports + resolve ----------
const waitForResolve = Number(resolveAt) - Math.floor(Date.now() / 1000) + 5;
console.log(`Step 5: waiting ${waitForResolve}s until resolveAt...`);
await new Promise(r => setTimeout(r, waitForResolve * 1000));
console.log(`  done.\n`);

console.log(`Step 6: oracle reporter submits metric value`);
const reportTx = await oracle.reportMetric(issueId, 2000n);  // > threshold (1000) → YES wins
console.log(`  report tx: ${EXPLORER}/tx/${reportTx}\n`);

console.log(`Step 7: anyone calls resolve()`);
const resolveTx = await proposer.resolve(issueId, "0x");
console.log(`  resolve tx: ${EXPLORER}/tx/${resolveTx}`);
const issueAfterResolve = await proposer.getIssue(issueId);
console.log(`  status:      ${issueAfterResolve.status} (Resolved)`);
console.log(`  metricMet:   ${issueAfterResolve.metricMet}`);
console.log(`  metricValue: ${issueAfterResolve.metricValue}\n`);

// ---------- step 8: claims ----------
console.log(`Step 8: both wallets claim`);
const c1 = await proposer.claim(issueId);
console.log(`  PROPOSER claim: ${EXPLORER}/tx/${c1.txHash}`);
console.log(`    payout: ${formatEther(c1.payout)} USDC`);

const c2 = await counter.claim(issueId);
console.log(`  COUNTER  claim: ${EXPLORER}/tx/${c2.txHash}`);
console.log(`    payout: ${formatEther(c2.payout)} USDC\n`);

console.log(`================== SUMMARY ==================`);
console.log(`Helm v0 full lifecycle executed on Arc Testnet via @helm/sdk:`);
console.log(`  - propose:   ${proposeTx}`);
console.log(`  - 4 bets:    ${b1}`);
console.log(`               ${b2}`);
console.log(`               ${b3}`);
console.log(`               ${b4}`);
console.log(`  - decide:    ${decideTx}`);
console.log(`  - oracle:    ${reportTx}`);
console.log(`  - resolve:   ${resolveTx}`);
console.log(`  - claims:    ${c1.txHash}  (payout ${formatEther(c1.payout)})`);
console.log(`               ${c2.txHash}  (payout ${formatEther(c2.payout)})`);
console.log(`Total bets locked: 0.004 USDC.   Total claimed: ${formatEther(c1.payout + c2.payout)} USDC.`);
console.log(`Verifiable: ${EXPLORER}/address/${HELM}`);
