import { encodeAbiParameters, keccak256, stringToHex } from "viem";
import type { Hex } from "./types.js";

/**
 * Helm derives issueId on-chain as keccak256(abi.encode(proposer, issueCount, chainId))
 * where issueCount is the post-increment counter. Useful for pre-computing the id
 * before propose() returns, e.g. for log filtering.
 */
export function deriveIssueId(proposer: Hex, issueCount: bigint, chainId: number | bigint): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "address" },
        { type: "uint256" },
        { type: "uint256" },
      ],
      [proposer, issueCount, BigInt(chainId)],
    ),
  );
}

/**
 * Convenience: hash an arbitrary metricKey string into bytes32.
 * The oracle is free to use any bytes32 schema; this is just the
 * common keccak256(utf8 label) pattern.
 */
export function metricKeyOf(label: string): Hex {
  return keccak256(stringToHex(label));
}
