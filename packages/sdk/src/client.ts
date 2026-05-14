import {
  createPublicClient,
  createWalletClient,
  http,
  type Account,
  type Address,
  type Chain,
  type PublicClient,
  type Transport,
  type WalletClient,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

import {
  CLAUDELANCE_CORE_ABI,
  MAINNET,
  SEPOLIA,
  type Bounty,
} from '@claudelance/types';

import { chainForNetwork, type NetworkKey } from './chain.js';
import { CUSD_ABI } from './cusd-abi.js';

/** Inputs accepted by {@link ClaudelanceClient.fromPrivateKey}. */
export type FromPrivateKeyOptions = {
  privateKey: `0x${string}`;
  network: NetworkKey;
  /** Override the default forno RPC; useful for an Alchemy/Infura key. */
  rpcUrl?: string;
};

/** Inputs accepted by the {@link ClaudelanceClient} constructor. */
export type ClaudelanceClientOptions = {
  publicClient: PublicClient;
  walletClient?: WalletClient<Transport, Chain, Account>;
  core: Address;
  /** ERC20 used by the bounty marketplace (cUSD on mainnet, MockCUSD on Sepolia). */
  cUSD: Address;
};

/** Optional payload accepted by {@link ClaudelanceClient.submitPR}. */
export type SubmitPROptions = {
  prUrl: string;
  commitHash: `0x${string}`;
  /** Free-form JSON the worker wants to attach (capabilities, model, notes). */
  metadata?: string;
};

/**
 * High-level read + write client for ClaudelanceCore. Wraps viem so an
 * agent only deals with marketplace concepts (bounty, claim, submit,
 * settle) and never has to think about viem ABI plumbing.
 *
 * Use the static {@link ClaudelanceClient.fromPrivateKey} factory for
 * the common case (agent runs with a single hot key). For composed
 * apps that already have a viem wallet client, instantiate directly.
 */
export class ClaudelanceClient {
  readonly publicClient: PublicClient;
  readonly walletClient?: WalletClient<Transport, Chain, Account>;
  readonly core: Address;
  readonly cUSD: Address;

  constructor(opts: ClaudelanceClientOptions) {
    this.publicClient = opts.publicClient;
    this.walletClient = opts.walletClient;
    this.core = opts.core;
    this.cUSD = opts.cUSD;
  }

  /**
   * Convenience: build a fully-wired client from a private key + network
   * key. Resolves the canonical Claudelance core address for the chosen
   * network from `@claudelance/types`.
   */
  static fromPrivateKey(opts: FromPrivateKeyOptions): ClaudelanceClient {
    const chain = chainForNetwork(opts.network);
    const account = privateKeyToAccount(opts.privateKey);
    const transport = http(opts.rpcUrl);

    const publicClient = createPublicClient({ chain, transport });
    const walletClient = createWalletClient({ chain, transport, account });

    const deployment = opts.network === 'celo' ? MAINNET : SEPOLIA;

    return new ClaudelanceClient({
      publicClient,
      walletClient,
      core: deployment.core,
      cUSD: deployment.cUSD,
    });
  }

  // ─── Read API ─────────────────────────────────────────────────────────

  /** Fetch a single bounty by id. */
  async getBounty(bountyId: bigint): Promise<Bounty> {
    return (await this.publicClient.readContract({
      address: this.core,
      abi: CLAUDELANCE_CORE_ABI,
      functionName: 'getBounty',
      args: [bountyId],
    })) as Bounty;
  }

  /** Total number of bounties ever posted. */
  async getBountyCount(): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: this.core,
      abi: CLAUDELANCE_CORE_ABI,
      functionName: 'bountyCount',
    })) as bigint;
  }

  /**
   * Return every currently-open bounty. Uses a multicall on the public
   * client so the request is one round-trip per `MAX_SLOTS`-sized batch.
   *
   * For very high `bountyCount` this scans linearly — fine for the
   * hackathon scope (hundreds at most). A future PR can subscribe to
   * `BountyPosted` events for an incremental cursor.
   */
  async listOpenBounties(): Promise<Array<Bounty & { id: bigint }>> {
    const count = await this.getBountyCount();
    if (count === 0n) return [];

    const calls = [];
    for (let i = 1n; i <= count; i++) {
      calls.push({
        address: this.core,
        abi: CLAUDELANCE_CORE_ABI,
        functionName: 'getBounty' as const,
        args: [i] as const,
      });
    }
    const results = await this.publicClient.multicall({
      contracts: calls,
      allowFailure: false,
    });

    const out: Array<Bounty & { id: bigint }> = [];
    for (let idx = 0; idx < results.length; idx++) {
      const b = results[idx] as Bounty;
      // status 0 == Open
      if (b.status === 0) out.push({ ...b, id: BigInt(idx + 1) });
    }
    return out;
  }

  /** Headline marketplace stats — useful for dashboards / agent self-reports. */
  async getStats(): Promise<{
    volume: bigint;
    revenue: bigint;
    resolved: bigint;
    posters: bigint;
    workers: bigint;
  }> {
    const [volume, revenue, resolved, posters, workers] =
      (await this.publicClient.readContract({
        address: this.core,
        abi: CLAUDELANCE_CORE_ABI,
        functionName: 'getStats',
      })) as readonly [bigint, bigint, bigint, bigint, bigint];
    return { volume, revenue, resolved, posters, workers };
  }

  /** Pending earnings (post-pickWinner payout + post-settleStake refunds) for an address. */
  async getEarnings(account: Address): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: this.core,
      abi: CLAUDELANCE_CORE_ABI,
      functionName: 'earnings',
      args: [account],
    })) as bigint;
  }

  /** Pending earnings for the wallet client's account; throws if no wallet was wired up. */
  async getMyEarnings(): Promise<bigint> {
    const me = this.requireAccount();
    return this.getEarnings(me);
  }

  /**
   * Eligibility check before claiming. Returns true only when:
   *  - bounty is Open
   *  - block.timestamp < bounty.deadline
   *  - bounty.claimedSlots < bounty.maxSlots
   *  - this client's account has not already claimed
   * Mirrors `claimSlot`'s on-chain guards so agents don't waste gas.
   */
  async canClaim(bountyId: bigint, account?: Address): Promise<boolean> {
    const who = account ?? this.requireAccount();
    const b = await this.getBounty(bountyId);
    if (b.status !== 0) return false;
    if (b.deadline <= BigInt(Math.floor(Date.now() / 1000))) return false;
    if (b.claimedSlots >= b.maxSlots) return false;

    const claimed = (await this.publicClient.readContract({
      address: this.core,
      abi: CLAUDELANCE_CORE_ABI,
      functionName: 'hasClaimed',
      args: [bountyId, who],
    })) as boolean;
    return !claimed;
  }

  // ─── Worker write API ────────────────────────────────────────────────

  /**
   * Claim a slot on a bounty. Reverts on chain if the bounty is closed,
   * the deadline has passed, slots are full, or the account has already
   * claimed. Prefer {@link claimSlotWithApproval} unless you've already
   * pre-approved cUSD spending.
   *
   * @returns the transaction hash. Await `publicClient.waitForTransactionReceipt`
   *          if you need confirmation before the next call.
   */
  async claimSlot(bountyId: bigint): Promise<`0x${string}`> {
    const wallet = this.requireWalletClient();
    return wallet.writeContract({
      address: this.core,
      abi: CLAUDELANCE_CORE_ABI,
      functionName: 'claimSlot',
      args: [bountyId],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Convenience: approve cUSD for the stake if needed, then claim the
   * slot. Skips the approval tx when the existing allowance is already
   * sufficient. Returns the claim tx hash.
   *
   * NOTE: emits up to 2 transactions. The approval tx is awaited so
   * `claimSlot` does not race ahead of an unmined approval.
   */
  async claimSlotWithApproval(bountyId: bigint): Promise<`0x${string}`> {
    const wallet = this.requireWalletClient();
    const who = wallet.account.address;
    const bounty = await this.getBounty(bountyId);
    const stake = bounty.stakeRequired;

    if (stake > 0n) {
      const allowance = (await this.publicClient.readContract({
        address: this.cUSD,
        abi: CUSD_ABI,
        functionName: 'allowance',
        args: [who, this.core],
      })) as bigint;
      if (allowance < stake) {
        const approveHash = await wallet.writeContract({
          address: this.cUSD,
          abi: CUSD_ABI,
          functionName: 'approve',
          args: [this.core, stake],
          account: wallet.account,
          chain: wallet.chain,
        });
        await this.publicClient.waitForTransactionReceipt({ hash: approveHash });
      }
    }
    return this.claimSlot(bountyId);
  }

  /**
   * Submit a PR for a claimed bounty. One-shot per (bountyId, worker) —
   * the contract rejects any subsequent submitPR even with corrected
   * inputs, so pass the final PR URL + head commit hash.
   */
  async submitPR(bountyId: bigint, opts: SubmitPROptions): Promise<`0x${string}`> {
    const wallet = this.requireWalletClient();
    return wallet.writeContract({
      address: this.core,
      abi: CLAUDELANCE_CORE_ABI,
      functionName: 'submitPR',
      args: [bountyId, opts.prUrl, opts.commitHash, opts.metadata ?? ''],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Settle a single claimer's stake on a resolved or cancelled bounty.
   * Permissionless — anyone can call for any worker; the contract
   * enforces the refund-vs-forfeit rules identically regardless of
   * caller. Defaults to settling the wallet account's own stake.
   */
  async settleStake(bountyId: bigint, worker?: Address): Promise<`0x${string}`> {
    const wallet = this.requireWalletClient();
    return wallet.writeContract({
      address: this.core,
      abi: CLAUDELANCE_CORE_ABI,
      functionName: 'settleStake',
      args: [bountyId, worker ?? wallet.account.address],
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  /**
   * Pull-pattern withdrawal: transfers every cUSD credited to the wallet
   * account (winner payouts, stake refunds, poster cancellation refunds,
   * accrued treasury fees) to the wallet in one transaction. Always
   * callable, even when the contract is paused.
   */
  async withdrawEarnings(): Promise<`0x${string}`> {
    const wallet = this.requireWalletClient();
    return wallet.writeContract({
      address: this.core,
      abi: CLAUDELANCE_CORE_ABI,
      functionName: 'withdrawEarnings',
      account: wallet.account,
      chain: wallet.chain,
    });
  }

  // ─── Internal helpers ────────────────────────────────────────────────

  /** @internal */
  protected requireAccount(): Address {
    const acct = this.walletClient?.account?.address;
    if (!acct) {
      throw new Error(
        '[ClaudelanceClient] No wallet client wired up — use fromPrivateKey() ' +
          'or pass a walletClient to the constructor.'
      );
    }
    return acct;
  }

  /** @internal */
  protected requireWalletClient(): WalletClient<Transport, Chain, Account> {
    if (!this.walletClient) {
      throw new Error(
        '[ClaudelanceClient] Write methods require a wallet client — use ' +
          'fromPrivateKey() or pass a walletClient to the constructor.'
      );
    }
    return this.walletClient;
  }
}
