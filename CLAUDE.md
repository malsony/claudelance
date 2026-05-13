# Claudelance — Working Notes for Claude

> The first onchain marketplace where idle Claude Code subscriptions earn cUSD by solving GitHub bounties.
> Hackathon: Celo Proof of Ship #8 (May 4-29, 2026). Submission Day 7 (May 21).
> Full spec lives in `Blueprint.md` — that file is the source of truth; read it before assuming.

## Locked decisions (do not re-litigate)

| Topic | Decision |
|-------|----------|
| Name / GitHub org | `claudelance` |
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

## Repo structure (target — not yet scaffolded)

```
claudelance/                                # monorepo (pnpm workspace)
├── contracts/                              # Foundry, Solidity 0.8.24
├── apps/
│   ├── web/                                # Next.js 15 MiniPay app
│   └── relayer/                            # Hono + SQLite indexer + CI verifier
└── packages/                               # npm-published
    ├── worker/                             # @claudelance/worker  (Day 4)
    ├── types/                              # @claudelance/types   (Day 6)
    ├── contracts/                          # @claudelance/contracts (Day 9)
    ├── sdk/                                # @claudelance/sdk     (Day 11)
    ├── react/                              # claudelance-react    (Day 13)
    └── cli/                                # @claudelance/cli     (Day 15)
```

Supplementary repos under `github.com/claudelance/`: `bounties-registry` (Phase 1), `content-submissions`, `video-submissions`, etc. (Phase 2).

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

Single contract — `ReentrancyGuard + Ownable + Pausable`. Public mutating fns:
- Employer: `postBounty`, `pickWinner`, `cancelExpired`
- Worker: `claimSlot`, `submitPR`, `withdrawEarnings`
- Relayer: `attestCI`
- Admin: `setCIRelayer`, `setTreasury`, `pause`, `unpause`

Constants: `PROTOCOL_FEE_BPS = 200` (2%), `MAX_SLOTS = 20`, `MIN_DEADLINE = 1 days`, `MAX_DEADLINE = 14 days`, `MIN_BOUNTY = 0.5e18`.

Stats are public state vars (`totalBountyVolume`, `totalProtocolRevenue`, etc.) + `getStats()` view for judges.

Per-bounty tx count target: ~25 (deposit + 5 claims + 5 PRs + 5 CI attests + winner pick + 3 refunds + 5 rep updates).

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
- Smart contracts are immutable on mainnet — flagged as Critical risk. Every contract diff goes through `/security-review` before commit.
- PR descriptions on worker-generated PRs MUST include: `Closes #<issue>`, `Claudelance Bounty: #<id>`, `Agent: claudelance-worker-#<id>`.
- Worker rate limit: 30 GitHub req/min.
- Mainnet deploys go through `--verify` flag against Celoscan.
- Indonesian (Bahasa) is fine in chat; code, comments, commit messages stay in English.

## Critical timeline

- Day 0 (TODAY, 2026-05-14): admin setup — register org, npm scope, Talent Passport, fund wallet (~$5 CELO + ~$30 cUSD), domain
- Day 1: `ClaudelanceCore.sol` + 20 tests + Sepolia deploy
- Day 4: publish `@claudelance/worker`
- Day 6: mainnet deploy + Vercel deploy + publish `@claudelance/types`
- Day 7 (2026-05-21): submission deadline — KarmaGAP + 15 seed bounties + 4-min demo video + pitch deck + Talent Protocol submit
- Day 8-15: sustained activity, onboard workers, publish remaining 4 npm packages
- Day 29 (2026-05-29): hackathon ends
