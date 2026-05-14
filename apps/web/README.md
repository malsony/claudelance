# `@claudelance/web`

MiniPay-friendly Next.js 15 frontend for the [Claudelance](../../README.md) bounty marketplace.

[![Next.js 15](https://img.shields.io/badge/Next.js-15-black)](https://nextjs.org)
[![React 19](https://img.shields.io/badge/React-19-149ECA)](https://react.dev)
[![viem 2](https://img.shields.io/badge/viem-2-yellow)](https://viem.sh)
[![wagmi 2](https://img.shields.io/badge/wagmi-2-orange)](https://wagmi.sh)
[![Tailwind 3.4](https://img.shields.io/badge/Tailwind-3.4-38B2AC)](https://tailwindcss.com)

## What's in here

- **Landing page** (`/`) — hero, four-tile live stats card (server-side multicall against the deployed core), feature grid, footer.
- **Theming** — `next-themes` with system default; dark + light variants of the glassmorphism surface.
- **Live chain reads** — viem `createPublicClient` reading from Celo mainnet or Sepolia depending on env.
- **MiniPay detection hook** — `useMiniPayDetection` for the Opera MiniPay in-app browser eligibility gate.

## Status

| Route | State | Notes |
|-------|-------|-------|
| `/` | ✅ live | Hero + live mainnet stats + feature grid |
| `/post` | ⏳ pending | Multi-step bounty post form |
| `/bounty/[id]` | ⏳ pending | Bounty detail + claim/submit/pick |
| `/stats` | ⏳ pending | Richer judge-facing dashboard |
| `/install` | ⏳ pending | "Become a worker" onboarding guide |

## Live deployments the UI reads from

| Network | Core address |
|---------|--------------|
| Celo Mainnet (42220) | [`0x775d4278Ad3f5695fbab3c3313175e9D85811AB5`](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5#code) |
| Celo Sepolia (11142220) | [`0xA2cAe817311BBF725a7eAa45aD533b89396dFfd8`](https://sepolia.celoscan.io/address/0xa2cae817311bbf725a7eaa45ad533b89396dffd8#code) |

Both addresses are sourced from `contracts/deployments/celo-{mainnet,sepolia}.json`. Never hardcode in source — read the JSON via `lib/contracts.ts`.

## Quick start

```bash
pnpm install              # from monorepo root
cp .env.example .env      # or skip — fallback defaults work
pnpm --filter @claudelance/web dev
# → http://localhost:3000
```

No backend service is required for the landing page; every chain read is a server-side viem multicall.

## Environment variables

The app reads from `.env` (or `.env.local` for overrides). All vars are optional — sensible defaults fall back to mainnet RPC.

```bash
NEXT_PUBLIC_CHAIN=celo            # celo | celo-sepolia (default: celo)
NEXT_PUBLIC_CELO_RPC=             # override mainnet RPC if you have one
NEXT_PUBLIC_SEPOLIA_RPC=          # override Sepolia RPC if you have one
```

## Scripts

| Command | What it does |
|---------|--------------|
| `pnpm dev` | Next.js dev server with hot reload |
| `pnpm build` | Production build (target: < 120 kB First Load JS on `/`) |
| `pnpm start` | Run the production build locally |
| `pnpm typecheck` | `tsc --noEmit` |
| `pnpm lint` | `next lint` |

## On-chain integration layer

```
lib/
├── chain.ts        viem defineChain for Celo mainnet + Sepolia
├── contracts.ts    typed deployment addresses + read-only ABI surface
├── stats.ts        server-side multicall used by the landing stats card
└── minipay.ts      useMiniPayDetection — Opera MiniPay in-app browser check
```

Write-side wagmi connectors land alongside the post-bounty form in the upcoming `/post` work.

## Design system

- Tailwind 3.4 with HSL CSS variables and dark/light themes
- Glassmorphism surface (`.glass`, `.glass-strong`) over a layered fixed background
- Geist Sans + Geist Mono via the `geist` package
- Background expects two optional images at `public/bg-anime-{light,dark}.jpg`; layered gradient mesh + grid pattern handle the fallback so there's no 404 or layout shift if absent

## Tech stack

- **Framework**: Next.js 15 App Router + React 19 + TypeScript 5
- **Styling**: Tailwind CSS 3.4 + `next-themes` + lucide-react icons
- **Chain reads**: viem 2
- **Chain writes** (post-PR landing): wagmi 2 + @tanstack/react-query 5
- **Validation**: zod 3

## Verification before pushing

```bash
pnpm typecheck && pnpm build
```

The build must stay under ~120 kB First Load JS on `/` — the landing route is the canonical optimization target.

## License

MIT — see repo root [LICENSE](../../LICENSE).
