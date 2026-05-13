/**
 * Retry the COUNTER wallet's claim from the prior full-lifecycle run. The
 * Arc Testnet RPC's mempool returned "txpool is full" on the second-to-last
 * claim of the demo. This is a known Arc Testnet quirk documented in
 * docs/spec.md and the submission's Product Feedback section.
 *
 * The protocol state is already correct on chain — propose/bet/decide/
 * resolve all succeeded, and PROPOSER's claim landed. We just need to
 * re-submit COUNTER's claim.
 */

import { formatEther } from "viem";
import { HelmClient, HELM_ARC_TESTNET, ARC_TESTNET, type Hex } from "../src/index.js";

process.loadEnvFile("D:\\桌面\\arc\\.env");

const SERVICE_PK = process.env.SERVICE_PRIVATE_KEY as Hex;
if (!SERVICE_PK) throw new Error("Missing SERVICE_PRIVATE_KEY");

// The issueId from the prior lifecycle run.
const ISSUE_ID: Hex = "0xc003ec854ac99d1054541f6160568b13bff6f4e443bbaa25422ff3392eb29d46";

const counter = new HelmClient({ privateKey: SERVICE_PK, helmAddress: HELM_ARC_TESTNET.helm });

console.log(`Retrying COUNTER.claim(${ISSUE_ID})...`);
console.log(`COUNTER address: ${counter.address}`);

let attempt = 0;
const MAX = 5;
while (attempt < MAX) {
  attempt++;
  try {
    const { txHash, payout } = await counter.claim(ISSUE_ID);
    console.log(`  attempt ${attempt}: ${ARC_TESTNET.explorer}/tx/${txHash}`);
    console.log(`  COUNTER payout: ${formatEther(payout)} USDC`);
    console.log(`  done.`);
    break;
  } catch (e: any) {
    const msg = String(e?.message ?? e).slice(0, 200);
    console.log(`  attempt ${attempt} FAILED: ${msg}`);
    if (attempt < MAX) {
      const sleepMs = 5000 * attempt;
      console.log(`  sleeping ${sleepMs}ms before retry...`);
      await new Promise(r => setTimeout(r, sleepMs));
    } else {
      console.error("All retries exhausted.");
      process.exit(1);
    }
  }
}
