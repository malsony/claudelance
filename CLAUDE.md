# Claudelance — Working Notes for Claude

> The first onchain marketplace where idle Claude Code subscriptions earn cUSD by solving GitHub bounties.
> Hackathon: Celo Proof of Ship #8 (May 4-29, 2026). Submission Day 7 (May 21).
> Full spec lives in `Blueprint.md`. Live deployment record: `contracts/deployments/celo-mainnet.json`.

## Locked decisions (do not re-litigate)

| Topic | Decision |
|-------|----------|
| Project name | `claudelance` (npm names: `@yeheskieltame/claudelance-*`, matches GitHub owner for Packages registry compat) |
| GitHub host | `github.com/yeheskieltame` (personal account, no org) |
| LLM (Phase 1) | Claude Code CLI only |
| Worker wallet | Dual mode: generate locally OR provide existing |
| Worker GitHub auth | Operator's Personal Access Token |
| Bidding | Poster-defined max slots, merit-based winner |
| Worker stake | 0.05 cUSD anti-sybil, refundable |
| Protocol fee | 2% on resolved bounties |
| Submission method | Unified: GitHub PR (all bounty types) |
| Off-chain config | `claudelance/bounties-registry` (JSON), keccak256 hash onchain |
| Phase 1 UI bounty types | Code only |
| Smart contract bounty types | 0-255 (future-proof) |
| Hackathon tracks | MiniApps + AI Powered Apps & Agents (dual entry) |
| npm strategy | 2 packages by Day 7 + 4 more Day 9-15 |
| Contract base | `ReentrancyGuard + Ownable2Step + Pausable` (immutable, no upgrade proxy) |
| Stake settlement | Pull pattern via `settleStake(bountyId, worker)` — `pickWinner` stays O(1) |
| Treasury payout | Pull pattern via `earnings[treasury]` — no push transfers to recipients |
| Admin key rotation | 2-day timelock + 14-day validity window on `treasury` / `ciRelayer` rotation |
| Mainnet wallet topology | 4 distinct keys — `Deploy.s.sol` aborts on chainid 42220 if any collide. Owner is a Safe multisig. |
| Mainnet deployer | Must be the user's Talent-registered address (`0x77c4a1c…`) for Celo Proof of Ship attribution |

## Repo structure

| Path | Status | Notes |
|------|--------|-------|
| `contracts/` | live (mainnet + Sepolia) | Foundry, Solidity 0.8.24, OZ v5 |
| `apps/web/` | in progress | Next.js 15 MiniPay app (landing + stats live) |
| `apps/relayer/` | planned (Day 5) | Hono + SQLite indexer + CI verifier |
| `packages/worker/` | planned (Day 4) | `@yeheskieltame/claudelance-worker` Claude Code CLI |
| `packages/types/` | published-ready | `@yeheskieltame/claudelance-types` shared ABI + types |
| `packages/sdk/` | published-ready | `@yeheskieltame/claudelance-sdk` agent client |
| `packages/contracts/` | planned (Day 9) | `@yeheskieltame/claudelance-contracts` ABI artifacts |
| `packages/react/` | planned (Day 13) | `claudelance-react` hooks |
| `packages/cli/` | planned (Day 15) | `@yeheskieltame/claudelance-cli` (binaries `claudelance` and `cln`) |

Supplementary repos under `github.com/yeheskieltame/`: `bounties-registry` (Phase 1 JSON spec hashed on-chain), `content-submissions`, `video-submissions` (Phase 2).

## Tech stack pinned versions

- Solidity `0.8.24`, Foundry nightly, OpenZeppelin `^5.0.0`, forge-std `^1.9.0`
- Next.js `15.x` (App Router), React `19.x`, TS `5.x`, Tailwind `3.4.x`, shadcn/ui
- viem `^2.21.0`, wagmi `^2.12.0`, @tanstack/react-query `^5.x`, zod `^3.x`
- Worker: Node `>=20`, @octokit/rest `^21.x`, simple-git `^3.x`, commander `^12.x`, inquirer `^10.x`, bip39 `^3.x`
- Relayer: Hono `^4.x`, better-sqlite3 `^11.x`, @octokit/webhooks `^13.x`, pino `^9.x`

## Networks & token

- Dev: Celo Sepolia — `https://forno.celo-sepolia.celo-testnet.org/`
- Prod: Celo Mainnet — `https://forno.celo.org`
- cUSD mainnet: `0x765DE816845861e75A25fCA122bb6898B8B1282a`
- Faucet: https://faucet.celo.org/celo-sepolia

## Smart contract surface (`ClaudelanceCore.sol`)

Single contract — `ReentrancyGuard + Ownable2Step + Pausable`. Public mutating fns:
- Employer: `postBounty`, `pickWinner`, `cancelExpired`
- Worker: `claimSlot`, `submitPR`, `withdrawEarnings`
- Anyone (permissionless after resolution): `settleStake(bountyId, worker)` — pull-pattern stake settlement
- Relayer: `attestCI`
- Admin (2-day timelock + 14-day validity window): `proposeTreasury`, `applyTreasury`, `cancelPendingTreasury`, `proposeCIRelayer`, `applyCIRelayer`, `cancelPendingCIRelayer`, `pause`, `unpause`, `rescueERC20`

Constants: `PROTOCOL_FEE_BPS = 200` (2%), `MAX_SLOTS = 20`, `MIN_DEADLINE = 1 days`, `MAX_DEADLINE = 14 days`, `MIN_BOUNTY = 0.5e18`, `RESOLUTION_GRACE_PERIOD = 3 days`, `ADMIN_TIMELOCK = 2 days`, `PROPOSAL_VALIDITY_WINDOW = 14 days`.

Stats are public state vars (`totalBountyVolume`, `totalProtocolRevenue`, etc.) + `getStats()` view for judges.

Per-bounty tx count: posting + N claims + N submits + N attests + pickWinner + N settleStake + worker withdraws. Poster's hot path (`pickWinner`) is O(1) — ~136k gas regardless of slot count.

### Mainnet deployment

| Role | Address |
|------|---------|
| ClaudelanceCore (verified) | `0x775d4278Ad3f5695fbab3c3313175e9D85811AB5` on chain 42220 |
| cUSD | `0x765DE816845861e75A25fCA122bb6898B8B1282a` |
| owner | `0xe9Fc48f315fD4E989637fAcC29AaF2717E19f7F0` (Safe multisig, 2 signers, threshold=1 — change to 2 via Safe UI for full multisig safety) |
| treasury | `0xCC0cCac212999612BdDdEb607B33CC1a46F8A401` |
| ciRelayer | `0x1fEDda23c2945D59f3929e6C463cF685aC077ad5` |
| deployer | `0x77c4a1cD22005b67Eb9CcEaE7E9577188d7Bca82` (Talent Protocol registered) |

Sepolia staging: ClaudelanceCore `0xA2cAe817311BBF725a7eAa45aD533b89396dFfd8`, MockCUSD `0x207D662337694796E76a4d5577DC72C93Cd92822`. See `contracts/deployments/celo-{mainnet,sepolia}.json` for full state.

## MCP / tooling installed (Day 0)

| Tool | Purpose |
|------|---------|
| celo-mcp | Chain data (balance, tx, contract, governance, staking) — Blueprint Section 13 required |
| github MCP (HTTP) | Repo/PR/issue/workflow management via natural language (OAuth on first use) |
| context7 MCP | Up-to-date docs for Next.js 15, viem, wagmi, Foundry, OpenZeppelin v5 |
| gh CLI | Local git+GitHub operations, `gh auth login` required before use |
| foundry / forge | Smart contract dev (already installed) |
| pnpm, node v25 | Monorepo + worker CLI |

Built-in skills relevant: `/security-review` (run before every contract commit), `/review` (worker PR review), `/init`.

## Submission scoring axes (always optimize for these)

1. **Onchain** — Celo mainnet tx, unique users, contract activity (target 1,945+ tx)
2. **GitHub** — commits, PRs, stars, contributions (target 150+ commits, 100+ PRs)
3. **Revenue** — value transacted + fees (target $250+ volume, $5+ fee)
4. **npm** — packages + weekly downloads (6 packages, 50+ downloads)

Eligibility gates that must pass: MiniPay-compatible (`useMiniPayDetection`), Celo mainnet deploy (verified Celoscan), Talent Protocol + KarmaGAP submission.

## Working conventions

- Treat Blueprint.md as authoritative for decisions; ask before deviating.
- Smart contracts are immutable on mainnet. Every contract diff goes through `/security-review`, Slither, and the invariant suite (`forge test --match-path "test/invariant/*"`) before commit.
- All post-Day-1 changes ship via `kiel-dev` branch, then PR, then self-review, then `gh pr merge --merge --delete-branch`. Per-file commits are preferred; per-context PRs are preferred over kitchen-sink PRs (more commits + PRs improve hackathon scoring).
- PR descriptions on worker-generated PRs MUST include: `Closes #<issue>`, `Claudelance Bounty: #<id>`, `Agent: claudelance-worker-#<id>`.
- Worker rate limit: 30 GitHub req/min.
- Mainnet broadcasts go through `--verify` against Celoscan (Etherscan API V2).
- Indonesian (Bahasa) is fine in chat; code, comments, commit messages stay in English.

### ABI migration notes for downstream tooling

Workers, relayers, frontends built against the contract must use the post-PR-11 surface:

- **Removed**: `setTreasury(address)` and `setCIRelayer(address)`. Use `proposeTreasury` / `applyTreasury` / `cancelPendingTreasury` (and the relayer triplet) — 2-day timelock, anyone can call `applyX` after delay, owner can cancel any time before.
- **Added**: `settleStake(uint256 bountyId, address worker)` — permissionless, callable by anyone after the bounty leaves `Open`. Stake refunds NO LONGER auto-credit during `pickWinner`; workers (or a treasury bot) must call `settleStake` before `withdrawEarnings` to claim stake refunds.
- **Added events**: `TreasuryProposed`, `CIRelayerProposed`, `TreasuryProposalCancelled`, `CIRelayerProposalCancelled`.
- **Added errors**: `InvalidUrl`, `NoPendingChange`, `TimelockNotElapsed`, `ProposalExpired`, `BountyNotResolved`, `StakeAlreadySettled`, `NoStakeRequired`.
- `pickWinner` no longer emits `StakeRefunded` / `StakeForfeited` — those move to `settleStake`.

Owner-only mainnet actions must go through the Safe at <https://app.safe.global/home?safe=celo:0xe9Fc48f315fD4E989637fAcC29AaF2717E19f7F0>, not from a CLI key.

## Critical timeline

- Day 0 (2026-05-14): admin setup + `ClaudelanceCore.sol` + 67 unit / 4 invariant / 28 fork tests + **Sepolia + mainnet deploy** (both verified on Celoscan)
- Day 4: publish `@yeheskieltame/claudelance-worker`
- Day 6: Vercel deploy + publish `@yeheskieltame/claudelance-types`
- Day 7 (2026-05-21): submission deadline — KarmaGAP + 15 seed bounties + 4-min demo video + pitch deck + Talent Protocol submit
- Day 8-15: sustained activity, onboard workers, publish remaining 4 npm packages
- Day 29 (2026-05-29): hackathon ends
