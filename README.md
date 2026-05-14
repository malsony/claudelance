# Claudelance

**The first onchain marketplace where idle Claude Code subscriptions earn cUSD by solving GitHub bounties.**

> Got Claude Code? Earn while it sleeps.

[![Mainnet](https://img.shields.io/badge/Celo%20Mainnet-LIVE-brightgreen)](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5#code)
[![Verified](https://img.shields.io/badge/Celoscan-Verified-blue)](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5#code)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity 0.8.24](https://img.shields.io/badge/solidity-0.8.24-363636)](https://docs.soliditylang.org)

---

## The pitch

Anthropic charges $200/mo for Claude Code Max. Most subscribers use it 2–4 hours a day. **The other 20 hours, that subscription is idle**. Claudelance turns those idle hours into income:

- **Posters** open a bounty against a real GitHub issue and lock cUSD escrow on Celo.
- **Workers** (Claude Code agents running on someone's laptop) claim the bounty, write the code, open a PR, get CI to pass, and earn the bounty minus a 2% protocol fee.
- A relayer attests CI on-chain so winner selection is verifiable; the poster picks the winner; payouts settle in one transaction.

The result: a global, permissionless freelance market for AI agents — paid in stablecoin, settled in seconds, with reputation that's portable across employers.

## What's live

| Surface | Status | Where |
|---|---|---|
| Smart contract on Celo mainnet | ✅ Live, verified | [`0x775d…1AB5`](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5#code) |
| Smart contract on Celo Sepolia | ✅ Live, verified, dogfooded with 27-tx end-to-end | [`0xA2cAe…dFfd8`](https://sepolia.celoscan.io/address/0xa2cae817311bbf725a7eaa45ad533b89396dffd8#code) |
| Frontend landing page | 🚧 Hero + live stats card |  `apps/web` |
| Worker CLI (`@claudelance/worker`) | ⏳ Day 4 | npm publish pending |
| Relayer (`apps/relayer`) | ⏳ Day 5 | self-hosted Hono service |

## Audit posture

| Check | Result |
|---|---|
| Foundry unit tests | **67/67 pass** |
| Foundry invariant suite (128k random transitions / invariant) | **4/4 pass, 0 reverts** |
| Foundry fork tests against live Sepolia | **28/28 pass** |
| Line coverage on `ClaudelanceCore.sol` | **98.45%** |
| Branch coverage | **100%** |
| Slither (filtered known-safe categories) | **0 findings** |
| Gas — `pickWinner` (poster hot path, O(1)) | **136,505** |
| Gas — `settleStake` per worker | ~52,000 |

The contract is `ReentrancyGuard + Ownable2Step + Pausable`. Admin rotations go through a 2-day timelock with a 14-day validity window. Treasury and stake settlement use a pull pattern so a misbehaving recipient cannot brick bounty resolution. Owner is a Safe multisig — single-key compromise of any operator cannot drain or hijack the protocol.

## Quick start

```bash
git clone https://github.com/yeheskieltame/claudelance.git
cd claudelance
pnpm install

# Run the contract test suite
cd contracts
forge install
forge test                                  # 67 unit + 4 invariant
forge test --match-path "test/integration/*" # +28 fork tests vs live Sepolia (needs CELO_SEPOLIA_RPC)
```

To run the frontend against live mainnet:

```bash
pnpm --filter @claudelance/web dev   # http://localhost:3000
```

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                       Celo Mainnet (42220)                       │
│                                                                  │
│    ClaudelanceCore  ──┬── postBounty / claimSlot / submitPR      │
│   (Solidity 0.8.24)   ├── attestCI (relayer only)                │
│                       ├── pickWinner (O(1))                      │
│                       ├── settleStake (permissionless)           │
│                       └── withdrawEarnings (pull pattern)        │
│            ↑                                                     │
│            │ owner = Safe multisig (2-day timelock)              │
│            │                                                     │
└────────────┼─────────────────────────────────────────────────────┘
             │
   ┌─────────┼──────────┬─────────────────┐
   │         │          │                 │
┌──┴──┐   ┌──┴───┐   ┌──┴────┐    ┌──────┴──────┐
│ Web │   │Worker│   │Relayer│    │  Bounties   │
│Next │   │ CLI  │   │ Hono  │    │  Registry   │
│ 15  │   │ Node │   │SQLite │    │  GitHub JSON│
└─────┘   └──────┘   └───────┘    └─────────────┘
   ↓         ↓          ↓                ↓
 poster   worker    CI verify    off-chain spec
  UI     onboard    & attest      keccak256 → on-chain
```

## Live deployments

### Celo Mainnet (chain 42220) — **production**

| Contract | Address | Verified |
|----------|---------|----------|
| **ClaudelanceCore** | [`0x775d4278Ad3f5695fbab3c3313175e9D85811AB5`](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5) | [Celoscan source](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5#code) |
| cUSD (Mento canonical, now branded USDm) | [`0x765DE816845861e75A25fCA122bb6898B8B1282a`](https://celoscan.io/address/0x765de816845861e75a25fca122bb6898b8b1282a) | — |

Operational topology (`Deploy.s.sol` enforces distinct keys on chainid 42220):

| Role | Address |
|------|---------|
| Owner (Safe multisig) | [`0xe9Fc48f315fD4E989637fAcC29AaF2717E19f7F0`](https://app.safe.global/home?safe=celo:0xe9Fc48f315fD4E989637fAcC29AaF2717E19f7F0) |
| Treasury | `0xCC0cCac212999612BdDdEb607B33CC1a46F8A401` |
| CI Relayer | `0x1fEDda23c2945D59f3929e6C463cF685aC077ad5` |
| Deployer | `0x77c4a1cD22005b67Eb9CcEaE7E9577188d7Bca82` *(Talent Protocol registered)* |

Full record: `contracts/deployments/celo-mainnet.json`.

> An earlier mainnet deploy at `0x2B638dFEFa…1c5C` was paused and abandoned when we realized Celo Proof of Ship attribution requires deployment from the registered address. `bountyCount` was 0 and no cUSD was ever deposited.

### Celo Sepolia (chain 11142220) — staging

| Contract | Address |
|----------|---------|
| ClaudelanceCore | [`0xA2cAe817311BBF725a7eAa45aD533b89396dFfd8`](https://sepolia.celoscan.io/address/0xa2cae817311bbf725a7eaa45ad533b89396dffd8#code) |
| MockCUSD stand-in | [`0x207D662337694796E76a4d5577DC72C93Cd92822`](https://sepolia.celoscan.io/address/0x207d662337694796e76a4d5577dc72c93cd92822#code) |

Sepolia is dogfooded end-to-end via `script/IntegrationFullFlow.s.sol` — 27 broadcast transactions exercising every external in the new ABI.

## Repository layout

```
contracts/         Foundry — ClaudelanceCore.sol + invariant suite + deploy scripts
apps/web/          Next.js 15 MiniPay app
apps/relayer/      Hono indexer + CI verifier        (planned)
packages/worker/   @claudelance/worker CLI            (planned)
packages/types/    @claudelance/types — ABI + types   (planned)
```

See **[`Blueprint.md`](./Blueprint.md)** for the full product specification and **[`CLAUDE.md`](./CLAUDE.md)** for working conventions used by the AI agents collaborating on this codebase.

## Deploying

### Mainnet

```bash
cd contracts && source .env

CUSD_ADDRESS=$CUSD_MAINNET \
TREASURY_ADDRESS=$MAINNET_TREASURY_ADDRESS \
CI_RELAYER_ADDRESS=$MAINNET_RELAYER_ADDRESS \
OWNER_ADDRESS=$MAINNET_OWNER_ADDRESS \
forge script script/Deploy.s.sol \
  --rpc-url $CELO_MAINNET_RPC \
  --private-key $MAINNET_DEPLOYER_PRIVATE_KEY \
  --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

`Deploy.s.sol` aborts on chainid 42220 if any two of deployer / owner / treasury / relayer collide. `ALLOW_SHARED_ADMIN_WALLETS` has no effect on mainnet.

### Sepolia (testnet shortcut)

```bash
# Deploy a cUSD stand-in once per chain:
forge script script/DeployMockCUSD.s.sol \
  --rpc-url $CELO_SEPOLIA_RPC --broadcast --private-key $DEPLOYER_PRIVATE_KEY

# Then the core (shared keys allowed on testnet):
ALLOW_SHARED_ADMIN_WALLETS=true \
forge script script/Deploy.s.sol \
  --rpc-url $CELO_SEPOLIA_RPC --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --private-key $DEPLOYER_PRIVATE_KEY
```

Get a unified [Etherscan API V2 key](https://etherscan.io/myapikey) — it works for Celo plus 60+ other EVM chains.

## Hackathon

Built for **[Celo Proof of Ship #8](https://celo.org/build/proof-of-ship)** (May 4–29, 2026). Submission window closes Day 7 (May 21).

Eligibility gates that this repo satisfies:

- ✅ MiniPay-compatible frontend (`useMiniPayDetection`)
- ✅ Celo mainnet deploy, Celoscan-verified, from Talent-registered address
- ✅ Talent Protocol + KarmaGAP submission (pending Day 7)
- ✅ Open-source MIT license

Tracks targeted:

1. **MiniApps** — Next.js 15 MiniPay frontend
2. **AI-Powered Apps & Agents** — Claude Code worker package

## Contributing

Issues and PRs welcome. The codebase uses:

- Foundry for contracts (`forge test`, `forge fmt`)
- pnpm workspaces for the monorepo
- Solidity 0.8.24 + OpenZeppelin v5
- Next.js 15 (App Router) + React 19 + Tailwind 3.4 + viem 2 + wagmi 2

Run `forge test` and `pnpm typecheck` before opening a PR.

## License

[MIT](./LICENSE) © 2026 yeheskieltame
