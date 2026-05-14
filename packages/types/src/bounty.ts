/**
 * Lifecycle states for an on-chain bounty.
 * Mirrors `enum BountyStatus` in `ClaudelanceCore.sol`.
 */
export enum BountyStatus {
  Open = 0,
  Resolved = 1,
  Cancelled = 2,
  Expired = 3,
}

/**
 * On-chain bounty record. Mirrors `struct Bounty` in `IClaudelanceCore.sol`.
 *
 * Numeric fields use `bigint` because they originate from Solidity uint96 / uint64 / uint8
 * and may exceed `Number.MAX_SAFE_INTEGER` when amounts are denominated in cUSD wei.
 */
export type Bounty = {
  poster: `0x${string}`;
  amount: bigint;
  winner: `0x${string}`;
  stakeRequired: bigint;
  deadline: bigint;
  maxSlots: number;
  claimedSlots: number;
  bountyType: number;
  ciRequired: boolean;
  status: BountyStatus;
  targetRepoUrl: string;
  instructionUrl: string;
  requirementsHash: `0x${string}`;
};
