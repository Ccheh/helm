import { describe, it, expect } from "vitest";
import { deriveIssueId, metricKeyOf } from "../src/utils.js";
import { keccak256, stringToHex } from "viem";

describe("deriveIssueId", () => {
  const proposer = "0x1234567890abcdef1234567890abcdef12345678" as const;

  it("matches the on-chain keccak256(abi.encode(proposer, count, chainId)) shape", () => {
    // Spot check: derivation is deterministic
    const id1 = deriveIssueId(proposer, 1n, 5042002);
    const id2 = deriveIssueId(proposer, 1n, 5042002);
    expect(id1).toBe(id2);
    expect(id1).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it("returns different ids for different counters", () => {
    const id1 = deriveIssueId(proposer, 1n, 5042002);
    const id2 = deriveIssueId(proposer, 2n, 5042002);
    expect(id1).not.toBe(id2);
  });

  it("returns different ids for different proposers", () => {
    const other = "0x9999999999999999999999999999999999999999" as const;
    expect(deriveIssueId(proposer, 1n, 5042002))
      .not.toBe(deriveIssueId(other, 1n, 5042002));
  });

  it("returns different ids for different chains", () => {
    expect(deriveIssueId(proposer, 1n, 1))
      .not.toBe(deriveIssueId(proposer, 1n, 5042002));
  });

  it("accepts chainId as bigint or number", () => {
    expect(deriveIssueId(proposer, 1n, 5042002n))
      .toBe(deriveIssueId(proposer, 1n, 5042002));
  });
});

describe("metricKeyOf", () => {
  it("returns keccak256 of utf-8 bytes", () => {
    expect(metricKeyOf("portfolio_value")).toBe(keccak256(stringToHex("portfolio_value")));
  });

  it("differentiates labels", () => {
    expect(metricKeyOf("a")).not.toBe(metricKeyOf("b"));
  });

  it("empty string is a valid bytes32 (keccak256 of empty)", () => {
    const k = metricKeyOf("");
    expect(k).toMatch(/^0x[0-9a-f]{64}$/);
  });
});
