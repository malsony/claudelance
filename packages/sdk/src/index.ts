// Public surface for @claudelance/sdk.

// Agent-facing plain-text exports — `console.log(RULES)` to learn the
// marketplace before touching chain.
export { RULES } from './rules.js';
export { FLOW } from './flow.js';
export { FAQ } from './faq.js';

// Human-readable mirrors of on-chain constants.
export {
  CUSD_DECIMALS,
  PROTOCOL_FEE_BPS,
  BPS_DENOMINATOR,
  MAX_SLOTS,
  MIN_DEADLINE_SECONDS,
  MAX_DEADLINE_SECONDS,
  MIN_BOUNTY_WEI,
  RESOLUTION_GRACE_PERIOD_SECONDS,
  ADMIN_TIMELOCK_SECONDS,
  PROPOSAL_VALIDITY_WINDOW_SECONDS,
  BOUNTY_TIERS,
} from './constants.js';

// Re-export the foundational types for ergonomic single-import usage.
export {
  BountyStatus,
  CLAUDELANCE_CORE_ABI,
  MAINNET,
  SEPOLIA,
  deploymentByChainId,
  type Bounty,
  type Submission,
  type PendingAddress,
  type Deployment,
  type ClaudelanceCoreAbi,
} from '@claudelance/types';

// PR-H adds: ClaudelanceClient (read API + ctor + factories)
// PR-I adds: ClaudelanceClient worker writes
// PR-J adds: ClaudelanceClient poster writes + format utils
