import { describe, it, expect } from "vitest";
import {
  ARC_TESTNET,
  HELM_ARC_TESTNET,
  HELM_ABI,
  MANUAL_ORACLE_ABI,
  Branch,
  Side,
  Status,
} from "../src/index.js";

describe("ARC_TESTNET constant", () => {
  it("has the canonical Arc Testnet chainId", () => {
    expect(ARC_TESTNET.chainId).toBe(5042002);
  });
  it("has the public Arc Testnet RPC + explorer", () => {
    expect(ARC_TESTNET.rpc).toMatch(/^https:\/\/rpc\.testnet\.arc\.network/);
    expect(ARC_TESTNET.explorer).toMatch(/^https:\/\/testnet\.arcscan\.app/);
  });
});

describe("HELM_ARC_TESTNET addresses", () => {
  it("addresses are checksummed-lowercase 40-hex strings", () => {
    expect(HELM_ARC_TESTNET.helm).toMatch(/^0x[0-9a-f]{40}$/);
    expect(HELM_ARC_TESTNET.manualOracle).toMatch(/^0x[0-9a-f]{40}$/);
  });
  it("helm != manualOracle", () => {
    expect(HELM_ARC_TESTNET.helm).not.toBe(HELM_ARC_TESTNET.manualOracle);
  });
});

describe("Helm constants enum values", () => {
  it("Branch values match Solidity (X=0, NOT_X=1)", () => {
    expect(Branch.X).toBe(0);
    expect(Branch.NOT_X).toBe(1);
  });
  it("Side values match Solidity (YES=0, NO=1)", () => {
    expect(Side.YES).toBe(0);
    expect(Side.NO).toBe(1);
  });
  it("Status values match Solidity (None/Open/Decided/Resolved)", () => {
    expect(Status.None).toBe(0);
    expect(Status.Open).toBe(1);
    expect(Status.Decided).toBe(2);
    expect(Status.Resolved).toBe(3);
  });
});

describe("ABI surface", () => {
  it("HELM_ABI exposes the 5 lifecycle functions", () => {
    const names = HELM_ABI.filter(e => e.type === "function").map(e => e.name);
    expect(names).toContain("proposeIssue");
    expect(names).toContain("bet");
    expect(names).toContain("decide");
    expect(names).toContain("resolve");
    expect(names).toContain("claim");
  });
  it("HELM_ABI exposes the 4 view functions", () => {
    const names = HELM_ABI.filter(e => e.type === "function").map(e => e.name);
    expect(names).toContain("issues");
    expect(names).toContain("pools");
    expect(names).toContain("prices");
    expect(names).toContain("userBet");
  });
  it("HELM_ABI exposes the 5 events", () => {
    const events = HELM_ABI.filter(e => e.type === "event").map(e => e.name);
    expect(events).toContain("IssueProposed");
    expect(events).toContain("BetPlaced");
    expect(events).toContain("IssueDecided");
    expect(events).toContain("IssueResolved");
    expect(events).toContain("Claimed");
  });
  it("MANUAL_ORACLE_ABI exposes reportMetric + isReady + getMetric", () => {
    const names = MANUAL_ORACLE_ABI.filter(e => e.type === "function").map(e => e.name);
    expect(names).toContain("reportMetric");
    expect(names).toContain("isReady");
    expect(names).toContain("getMetric");
  });
});
