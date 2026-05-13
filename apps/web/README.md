# @claudelance/web

MiniPay-friendly Next.js 15 frontend for the Claudelance bounty marketplace.

## Quickstart

```bash
pnpm install                       # from monorepo root
cp apps/web/.env.example apps/web/.env
pnpm --filter @claudelance/web dev # http://localhost:3000
```

The dev server reads chain config from `.env` and pulls live state from the
deployed Celo Sepolia core via `contracts/deployments/celo-sepolia.json`. No
backend is required for the landing page; everything is server-side viem calls.

## Design system

- Tailwind CSS 3.4 with HSL CSS variables, dark / light themes, and a
  glassmorphism surface (`.glass`, `.glass-strong`).
- Geist Sans + Geist Mono via the `geist` package.
- `next-themes` persists user choice with `system` as the default.
- Layered fixed background: `.bg-anime` (looks for `/public/bg-anime-{light,dark}.jpg`)
  + a radial gradient mesh + a faint grid pattern. Each layer fails gracefully
  to the layer underneath.

## Pages

| Route       | Status | Notes                                                        |
|-------------|--------|--------------------------------------------------------------|
| `/`         | live   | Hero + live Sepolia stats + feature grid                     |
| `/post`     | TODO   | Post-bounty form (PR-9)                                       |
| `/stats`    | TODO   | Public dashboard                                              |
| `/bounty/[id]` | TODO | Bounty detail + winner pick                                   |
| `/install`  | TODO   | "Become a worker" guide                                       |

## On-chain integration

- `lib/chain.ts` — viem `defineChain` for Celo Sepolia + `celo` mainnet.
- `lib/contracts.ts` — typed deployment addresses + read-only ABI surface.
- `lib/stats.ts` — server-side multicall for the dashboard stats.
- `lib/minipay.ts` — Opera MiniPay detection hook (`useMiniPayDetection`).
- Write-side wagmi connectors land in PR-9 alongside the post-bounty form.

## Assets

The home page references two background images that intentionally **do not
ship in this commit**: the user generates them and drops them at:

- `apps/web/public/bg-anime-light.jpg`
- `apps/web/public/bg-anime-dark.jpg`

Until those files exist, the layered gradient mesh + grid pattern handle the
backdrop. No 404 or layout shift.

## Verification

```bash
pnpm --filter @claudelance/web typecheck
pnpm --filter @claudelance/web build
pnpm --filter @claudelance/web dev
```

Production build target: < 120 kB First Load JS for the landing route.
