# Claudelance — Working Notes for Claude

> The first onchain marketplace where idle Claude Code subscriptions earn cUSD, CELO, or USDC by solving GitHub bounties.
> Hackathon: Celo Proof of Ship #8 (May 4-29, 2026). Submission Day 7 (May 21).
> Full spec lives in `Blueprint.md`. Live deployment record: `contracts/deployments/celo-sepolia.json` (mainnet v2 deferred).

## Locked decisions (do not re-litigate)

| Topic | Decision |
|-------|----------|
| Project name | `claudelance` (npm names: `@yeheskieltame/claudelance-*`, matches GitHub owner for Packages registry compat) |
| GitHub host | `github.com/yeheskieltame` (personal account, no org) |
| LLM (Phase 1) | Claude Code CLI only |
| Worker wallet | Dual mode: generate locally OR provide existing |
| Worker GitHub auth | Operator's Personal Access Token |
| Worker identity | ERC-8004 Identity NFT required to `claimSlot` (Celo deployed registries) |
| Token whitelist | cUSD + CELO ERC20 + USDC; one-way `allowToken`; per-token `minBounty` mapping |
| Hire modes | Open marketplace (`postBounty`) OR direct hire (`postDirectHire`, single targeted worker) |
| Stake policy | `stake > 0` required on ALL bounties (open + direct) |
| Bidding | Poster-defined max slots, merit-based winner (open mode) or pre-selected worker (direct) |
| Protocol fee | 2% on resolved bounties, per-token accounting |
| Submission method | Unified: GitHub PR (all bounty types) |
| Off-chain config | `claudelance/bounties-registry` (JSON), keccak256 hash onchain |
| Phase 1 UI bounty types | Code only |
| Smart contract bounty types | 0-255 (future-proof) |
| Hackathon tracks | MiniApps + AI Powered Apps & Agents (dual entry) |
| npm strategy | 2 packages by Day 7 + 4 more Day 9-15 |
| Contract base | `ReentrancyGuard + Ownable2Step + Pausable` (immutable, no upgrade proxy) |
| Stake settlement | Pull pattern via `settleStake(bountyId, worker)` — `pickWinner` stays O(1) |
| Treasury payout | Pull pattern via `earnings[treasury][token]` — no push transfers to recipients |
| Admin key rotation | 2-day timelock + 14-day validity window on `treasury` / `ciRelayer` rotation |
| Mainnet wallet topology | 4 distinct keys — `Deploy.s.sol` aborts on chainid 42220 if any collide. Owner is a Safe multisig. |
| Mainnet deployer | Must be the user's Talent-registered address (`0x77c4a1c…`) for Celo Proof of Ship attribution |
| Mainnet v1 status | PAUSED + abandoned (zero state on-chain when paused); v2 mainnet deploy deferred until Sepolia E2E validation |

## Repo structure

| Path | Status | Notes |
|------|--------|-------|
| `contracts/` | v2 live on Sepolia; v1 mainnet paused | Foundry, Solidity 0.8.24, OZ v5 |
| `apps/web/` | needs v2 update | Next.js 15 MiniPay app (landing + stats live on v1 ABI) |
| `apps/relayer/` | planned (Day 5) | Hono + SQLite indexer + CI verifier |
| `packages/worker/` | planned (Day 4) | `@yeheskieltame/claudelance-worker` Claude Code CLI |
| `packages/types/` | v0.2.0 (multi-token + 8004 + direct hire); not yet republished | `@yeheskieltame/claudelance-types` shared ABI + types |
| `packages/sdk/` | v0.2.0; not yet republished | `@yeheskieltame/claudelance-sdk` agent client |
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

## Networks, tokens, registries

- Dev: Celo Sepolia — `https://forno.celo-sepolia.celo-testnet.org/`
- Prod (deferred): Celo Mainnet — `https://forno.celo.org`
- Mainnet token canonical addresses:
  - cUSD: `0x765DE816845861e75A25fCA122bb6898B8B1282a`
  - CELO ERC20: `0x471EcE3750Da237f93B8E339c536989b8978a438`
  - USDC: `0xcebA9300f2b948710d2653dD7B07f33A8B32118C`
- ERC-8004 (Celo-deployed):
  - Mainnet Identity: `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`
  - Mainnet Reputation: `0x8004BAa17C55a88189AE136b182e5fdA19dE9b63`
  - Sepolia Identity: `0x8004A818BFB912233c491871b3d84c89A494BD9e`
  - Sepolia Reputation: `0x8004B663056A597Dffe9eCcC1965A193B7388713`
- Faucet: https://faucet.celo.org/celo-sepolia

## Smart contract surface (`ClaudelanceCore.sol` v2)

Single contract — `ReentrancyGuard + Ownable2Step + Pausable`. Public mutating fns:
- Poster (open): `postBounty(token, ...)`
- Poster (direct hire): `postDirectHire(token, targetWorker, ...)` — forces `maxSlots=1`, `ciRequired=false`
- Poster (any): `pickWinner`, `cancelExpired`
- Worker: `claimSlot` (ERC-8004 gated + targetWorker gated), `submitPR`, `withdrawEarnings(token)`
- Anyone (permissionless after resolution): `settleStake(bountyId, worker)`
- Relayer: `attestCI`
- Admin (immediate): `allowToken(token, minAmount)` (one-way), `setMinBounty(token, amount)`
- Admin (2-day timelock + 14-day validity window): `proposeTreasury`, `applyTreasury`, `cancelPendingTreasury`, `proposeCIRelayer`, `applyCIRelayer`, `cancelPendingCIRelayer`, `pause`, `unpause`, `rescueERC20`

Constants: `PROTOCOL_FEE_BPS = 200` (2%), `MAX_SLOTS = 20`, `MIN_DEADLINE = 1 days`, `MAX_DEADLINE = 14 days`, `RESOLUTION_GRACE_PERIOD = 3 days`, `ADMIN_TIMELOCK = 2 days`, `PROPOSAL_VALIDITY_WINDOW = 14 days`. `MIN_BOUNTY` is now per-token (admin-set via `allowToken` / `setMinBounty`).

Stats are per-token: `totalBountyVolume[token]`, `totalProtocolRevenue[token]`. Globals: `totalBountiesResolved`, `uniquePosterCount`, `uniqueWorkerCount`, `bountyCount`, `bountyCountByType[type]`. View `getStats(token)` returns the 5-tuple for a single token; frontend aggregates across tokens via price oracle.

Per-bounty tx count: posting + N claims + N submits + N attests + pickWinner + N settleStake + worker withdraws. Poster's hot path (`pickWinner`) stays O(1).

### v2 Sepolia deployment (LIVE 2026-05-14)

| Role | Address |
|------|---------|
| ClaudelanceCore v2 (verified) | `0xC478e36CC213Cb459282b5B690bF8FF4975A911F` on chain 11142220 |
| MockCUSD | `0xeB9595f4d14A4AEB23cc535007c973e50F1307E7` (min 0.5 cUSD) |
| MockCELO | `0x68128f321E01C2388628c549E3a4Ea016DB01968` (min 1 CELO) |
| MockUSDC | `0x71f44190dCE495b663700A3e96909988b8fbF3F9` (min 0.5 USDC) |
| ERC-8004 Identity | `0x8004A818BFB912233c491871b3d84c89A494BD9e` (Celo-deployed) |
| ERC-8004 Reputation | `0x8004B663056A597Dffe9eCcC1965A193B7388713` (Celo-deployed) |
| owner / treasury / relayer | `0x987e2ed458ddAF6f900362F94558378056dCc226` (single key, Sepolia only) |

### v1 Mainnet (abandoned/paused — historical record)

| Role | Address |
|------|---------|
| ClaudelanceCore v1 (verified, paused) | `0x775d4278Ad3f5695fbab3c3313175e9D85811AB5` on chain 42220 |
| cUSD | `0x765DE816845861e75A25fCA122bb6898B8B1282a` |
| owner | `0xe9Fc48f315fD4E989637fAcC29AaF2717E19f7F0` (Safe multisig, 2 signers, threshold=1) |
| treasury | `0xCC0cCac212999612BdDdEb607B33CC1a46F8A401` |
| ciRelayer | `0x1fEDda23c2945D59f3929e6C463cF685aC077ad5` |
| deployer | `0x77c4a1cD22005b67Eb9CcEaE7E9577188d7Bca82` (Talent Protocol registered) |

Mainnet v2 will reuse these admin wallets when deployed.

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

### v1→v2 ABI migration notes

v1 mainnet (`0x775d…11AB5`) is paused. All downstream tooling must target v2 ABI on Sepolia (`0xC478e3…911F`).

**Breaking changes from v1 to v2:**
- `constructor` signature: `(treasury, ciRelayer, owner, identityRegistry, reputationRegistry)` — `cUSD` parameter removed
- `postBounty` adds `IERC20 token` as first parameter
- New: `postDirectHire(token, targetWorker, ..., stake, deadline)` — forces `maxSlots=1`, `ciRequired=false`
- `withdrawEarnings(IERC20 token)` — must specify which token to withdraw
- `earnings` is now `mapping(address => mapping(address => uint256))` — `earnings(addr, token)` lookup
- `getStats(IERC20 token)` — per-token stats
- `totalBountyVolume(token)`, `totalProtocolRevenue(token)` — mapping reads
- New: `allowToken(token, minBounty)` (onlyOwner, one-way), `setMinBounty(token, amount)`
- New errors: `TokenNotAllowed`, `TokenAlreadyAllowed`, `NotTargetedWorker`, `InvalidStake`, `NoAgentIdentity`, `CannotRescueEscrowToken`
- New `Bounty` fields: `token`, `targetWorker` (struct also reordered for packing — 4 fixed slots)
- `BountyPosted` event: adds `address token` (indexed), `address targetWorker`, `uint96 stakeRequired`
- `EarningsWithdrawn` event: adds `address token` (indexed)
- `ProtocolRevenueAccrued` event: adds `address token` (indexed)
- `MIN_BOUNTY` constant removed; use per-token `minBounty(token)` getter
- `CannotRescueCUSD` error renamed to `CannotRescueEscrowToken` (now blocks any whitelisted token)
- `claimSlot` revert paths: `NotTargetedWorker` (direct hire mismatch), `NoAgentIdentity` (missing ERC-8004 NFT)

**Stable across v1→v2:** `claimSlot(id)`, `submitPR`, `attestCI`, `pickWinner`, `cancelExpired`, `settleStake`, all timelock/treasury/relayer rotation fns, `pause` / `unpause`.

Owner-only mainnet actions must go through the Safe at <https://app.safe.global/home?safe=celo:0xe9Fc48f315fD4E989637fAcC29AaF2717E19f7F0>, not from a CLI key.

## Critical timeline

- Day 0 (2026-05-14): admin setup + `ClaudelanceCore` v1 deploy + 67 unit / 4 invariant / 28 fork tests + Sepolia + mainnet deploy
- Day 0 late (2026-05-14): **v2 pivot — multi-token + ERC-8004 + direct hire**; v1 mainnet paused, v2 deployed to Sepolia; types + sdk bumped to 0.2.0; 83 tests
- Day 4: publish `@yeheskieltame/claudelance-worker`
- Day 6: Vercel deploy + republish types/sdk 0.2.0 to npm + GH Packages
- Day 7 (2026-05-21): submission deadline — KarmaGAP + 15 seed bounties + 4-min demo video + pitch deck + Talent Protocol submit
- Day 8-15: sustained activity, onboard workers, publish remaining 4 npm packages
- Day 29 (2026-05-29): hackathon ends
