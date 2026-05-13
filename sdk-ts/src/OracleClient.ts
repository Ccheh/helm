import {
  createPublicClient,
  createWalletClient,
  http,
  type PublicClient,
  type WalletClient,
  type Account,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ARC_TESTNET, MANUAL_ORACLE_ABI, type ArcChain } from "./constants.js";
import type { Hex } from "./types.js";

export interface OracleClientOptions {
  privateKey: Hex;
  oracleAddress: Hex;
  chain?: ArcChain;
}

/**
 * Client for ManualMetricOracle — only the immutable `reporter` address
 * can submit metric values. In production deployments this would be
 * replaced by a validator-network adapter (e.g. Crucible TestcaseResolverV5),
 * with no equivalent client needed.
 */
export class OracleClient {
  readonly account: Account;
  readonly chain: ArcChain;
  readonly oracleAddress: Hex;
  readonly publicClient: PublicClient;
  readonly walletClient: WalletClient;

  constructor(opts: OracleClientOptions) {
    this.account = privateKeyToAccount(opts.privateKey);
    this.chain = opts.chain ?? ARC_TESTNET;
    this.oracleAddress = opts.oracleAddress;

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

  async reportMetric(issueId: Hex, value: bigint): Promise<Hex> {
    const txHash = await this.walletClient.writeContract({
      account: this.account,
      chain: this.walletClient.chain!,
      address: this.oracleAddress,
      abi: MANUAL_ORACLE_ABI,
      functionName: "reportMetric",
      args: [issueId, value],
    });
    await this.publicClient.waitForTransactionReceipt({ hash: txHash });
    return txHash;
  }

  async isReady(issueId: Hex): Promise<boolean> {
    return await this.publicClient.readContract({
      address: this.oracleAddress, abi: MANUAL_ORACLE_ABI,
      functionName: "isReady", args: [issueId],
    }) as boolean;
  }

  async getReporter(): Promise<Hex> {
    return await this.publicClient.readContract({
      address: this.oracleAddress, abi: MANUAL_ORACLE_ABI,
      functionName: "reporter", args: [],
    }) as Hex;
  }
}
