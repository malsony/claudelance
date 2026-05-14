import type { Bounty } from '@claudelance/types';
import { CUSD_DECIMALS } from './constants.js';

/**
 * Convert a cUSD wei amount (bigint, 18 decimals) to a plain number for
 * UI / log lines. Precision is lossy beyond ~15 decimal digits — fine
 * for human display, NEVER use the result for math that affects on-chain
 * state.
 */
export function cusdToFloat(wei: bigint): number {
  return Number(wei) / 10 ** CUSD_DECIMALS;
}

/**
 * Convert a human-readable cUSD amount (float) to wei (bigint).
 *
 * Rounds at the wei boundary. Caller is responsible for sanity-checking
 * the result against the contract's `MIN_BOUNTY_WEI` / per-tier rules.
 */
export function floatToCusd(amount: number): bigint {
  if (!Number.isFinite(amount) || amount < 0) {
    throw new Error(`[floatToCusd] amount must be a non-negative finite number, got ${amount}`);
  }
  return BigInt(Math.round(amount * 10 ** CUSD_DECIMALS));
}

/**
 * Pretty-print a cUSD wei amount with a fixed number of decimals.
 *
 *   cusdFormat(2_060_000_000_000_000_000n)        -> "2.06 cUSD"
 *   cusdFormat(123_456_789_000_000_000n, 4)       -> "0.1235 cUSD"
 */
export function cusdFormat(wei: bigint, decimals = 2): string {
  return `${cusdToFloat(wei).toFixed(decimals)} cUSD`;
}

/**
 * Seconds until a bounty's deadline, given the current wall clock. Can
 * be negative if the deadline has already passed.
 */
export function timeRemaining(bounty: Bounty, nowSeconds?: number): number {
  const now = nowSeconds ?? Math.floor(Date.now() / 1000);
  return Number(bounty.deadline) - now;
}

/**
 * One-line, agent-friendly summary of a bounty for log lines + LLM
 * prompts. Example:
 *
 *   "Bounty #42 OPEN | 2.50 cUSD | 3/5 slots | 2d 4h left | CI required
 *    | repo: github.com/foo/bar"
 */
export function formatBountySummary(bounty: Bounty & { id: bigint }): string {
  const statusLabel = ['OPEN', 'RESOLVED', 'CANCELLED', 'EXPIRED'][bounty.status] ?? '?';
  const remaining = timeRemaining(bounty);
  const days = Math.max(0, Math.floor(remaining / 86_400));
  const hours = Math.max(0, Math.floor((remaining % 86_400) / 3600));
  const left = remaining <= 0 ? 'EXPIRED' : `${days}d ${hours}h left`;
  const ci = bounty.ciRequired ? 'CI required' : 'no CI';
  return [
    `Bounty #${bounty.id} ${statusLabel}`,
    cusdFormat(bounty.amount),
    `${bounty.claimedSlots}/${bounty.maxSlots} slots`,
    left,
    ci,
    `repo: ${bounty.targetRepoUrl}`,
  ].join(' | ');
}
