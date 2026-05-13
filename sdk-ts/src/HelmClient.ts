import {
  createPublicClient,
  createWalletClient,
  http,
  type PublicClient,
  type WalletClient,
  type Account,
  decodeEventLog,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ARC_TESTNET, HELM_ABI, type ArcChain, Branch, Side } from "./constants.js";
import type { Hex, IssueParams, IssueState, PoolSnapshot, PriceSnapshot } from "./types.js";
import { deriveIssueId } from "./utils.js";

export interface HelmClientOptions {
  privateKey: Hex;
  helmAddress: Hex;
  chain?: ArcChain;
}

/**
 * Single-role client covering the full Helm lifecycle. Anyone can call any
 * function on Helm.sol — proposer / bettor / decider / resolver / claimer
 * are all msg.sender-distinguished but use the same contract surface. The
 * SDK keeps a single class to mirror that simplicity.
 */
export class HelmClient {
  readonly account: Account;
  readonly chain: ArcChain;
  readonly helmAddress: Hex;
  readonly publicClient: PublicClient;
  readonly walletClient: WalletClient;

  constructor(opts: HelmClientOptions) {
    this.account = privateKeyToAccount(opts.privateKey);
    this.chain = opts.chain ?? ARC_TESTNET;
    this.helmAddress = opts.helmAddress;

    const viemChain = {
      id: this.chain.chainId,
      name: "Arc Testnet",
      nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
      rpcUrls: { default: { http: [this.chain.rpc] } },
    } as const;

    this.publicClient = createPublicClient({ chain: viemChain, transport: http() });
    this.walletClient = createWalletClient({
      account: this.account, chain: viemChain, transport: http(),
    });
  }

  get address(): Hex {
    return this.account.address;
  }

  /**
   * Submit `proposeIssue`. Returns the on-chain tx hash plus the derived
   * issueId (computed locally from the post-call issueCount, verified
   * against the IssueProposed event).
   */
  async proposeIssue(params: IssueParams): Promise<{ txHash: Hex; issueId: Hex }> {
    const txHash = await this.walletClient.writeContract({
      account: this.account,
      chain: this.walletClient.chain!,
      address: this.helmAddress,
      abi: HELM_ABI,
      functionName: "proposeIssue",
      args: [
        params.metricOracle,
        params.metricKey,
        params.threshold,
        params.decideAt,
        params.resolveAt,
        params.defaultDecision,
      ],
    });
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash: txHash });

    // Decode IssueProposed to get the issueId — most reliable across reorg / chain quirks.
    for (const log of receipt.logs) {
      try {
        const decoded = decodeEventLog({ abi: HELM_ABI, data: log.data, topics: log.topics });
        if (decoded.eventName === "IssueProposed") {
          return { txHash, issueId: decoded.args.issueId as Hex };
        }
      } catch {/* not our event */}
    }
    throw new Error(`proposeIssue tx ${txHash} did not emit IssueProposed`);
  }

  async bet(issueId: Hex, branch: number, side: number, amountWei: bigint): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account,
      chain: this.walletClient.chain!,
      address: this.helmAddress,
      abi: HELM_ABI,
      functionName: "bet",
      args: [issueId, branch, side],
      value: amountWei,
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  }

  /** Convenience: bet on the X / YES pool (this branch's policy → metric > threshold) */
  betXYes(issueId: Hex, amountWei: bigint): Promise<Hex> { return this.bet(issueId, Branch.X, Side.YES, amountWei); }
  betXNo(issueId: Hex, amountWei: bigint): Promise<Hex> { return this.bet(issueId, Branch.X, Side.NO, amountWei); }
  betNotXYes(issueId: Hex, amountWei: bigint): Promise<Hex> { return this.bet(issueId, Branch.NOT_X, Side.YES, amountWei); }
  betNotXNo(issueId: Hex, amountWei: bigint): Promise<Hex> { return this.bet(issueId, Branch.NOT_X, Side.NO, amountWei); }

  async decide(issueId: Hex): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account,
      chain: this.walletClient.chain!,
      address: this.helmAddress,
      abi: HELM_ABI,
      functionName: "decide",
      args: [issueId],
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  }

  async resolve(issueId: Hex, oracleData: Hex = "0x"): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account,
      chain: this.walletClient.chain!,
      address: this.helmAddress,
      abi: HELM_ABI,
      functionName: "resolve",
      args: [issueId, oracleData],
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  }

  async claim(issueId: Hex): Promise<{ txHash: Hex; payout: bigint }> {
    const txHash = await this.walletClient.writeContract({
      account: this.account,
      chain: this.walletClient.chain!,
      address: this.helmAddress,
      abi: HELM_ABI,
      functionName: "claim",
      args: [issueId],
    });
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash: txHash });
    let payout = 0n;
    for (const log of receipt.logs) {
      try {
        const decoded = decodeEventLog({ abi: HELM_ABI, data: log.data, topics: log.topics });
        if (decoded.eventName === "Claimed" &&
            (decoded.args.user as Hex).toLowerCase() === this.address.toLowerCase()) {
          payout = decoded.args.amount as bigint;
        }
      } catch {/* not our event */}
    }
    return { txHash, payout };
  }

  /* ----- reads ----- */

  async getIssue(issueId: Hex): Promise<IssueState> {
    const r = await this.publicClient.readContract({
      address: this.helmAddress, abi: HELM_ABI, functionName: "issues", args: [issueId],
    }) as readonly [Hex, Hex, Hex, bigint, bigint, bigint, number, number, number, boolean, bigint];
    return {
      proposer: r[0], metricOracle: r[1], metricKey: r[2],
      threshold: r[3], decideAt: r[4], resolveAt: r[5],
      defaultDecision: r[6], status: r[7], chosenBranch: r[8],
      metricMet: r[9], metricValue: r[10],
    };
  }

  async getPools(issueId: Hex): Promise<PoolSnapshot> {
    const [xYes, xNo, notxYes, notxNo] = await this.publicClient.readContract({
      address: this.helmAddress, abi: HELM_ABI, functionName: "pools", args: [issueId],
    }) as readonly [bigint, bigint, bigint, bigint];
    return { xYes, xNo, notxYes, notxNo };
  }

  async getPrices(issueId: Hex): Promise<PriceSnapshot> {
    const [pX, pNotX] = await this.publicClient.readContract({
      address: this.helmAddress, abi: HELM_ABI, functionName: "prices", args: [issueId],
    }) as readonly [bigint, bigint];
    return { pX, pNotX };
  }

  async getIssueCount(): Promise<bigint> {
    return await this.publicClient.readContract({
      address: this.helmAddress, abi: HELM_ABI, functionName: "issueCount", args: [],
    }) as bigint;
  }

  async getUserBet(issueId: Hex, branch: number, side: number, user: Hex): Promise<bigint> {
    return await this.publicClient.readContract({
      address: this.helmAddress, abi: HELM_ABI, functionName: "userBet",
      args: [issueId, branch, side, user],
    }) as bigint;
  }

  /** Pre-compute the issueId for a proposeIssue call that hasn't run yet. */
  async previewNextIssueId(): Promise<Hex> {
    const cnt = await this.getIssueCount();
    return deriveIssueId(this.address, cnt + 1n, this.chain.chainId);
  }
}
