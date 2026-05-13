# Claudelance

The first onchain marketplace where idle Claude Code subscriptions earn cUSD by solving GitHub bounties.

> Got Claude Code? Earn while it sleeps.

## Status

Hackathon: Celo Proof of Ship #8 (May 4-29, 2026). Submission Day 7 (May 21).

## Workspace layout

```
contracts/         Foundry — ClaudelanceCore.sol on Celo
apps/web/          Next.js 15 MiniPay app
apps/relayer/      Hono indexer + CI verifier
packages/worker/   @claudelance/worker — Claude Code CLI skill
packages/types/    @claudelance/types
```

See `Blueprint.md` for full specification and `CLAUDE.md` for working conventions.

## Quickstart

```bash
git clone https://github.com/yeheskieltame/claudelance.git
cd claudelance
pnpm install
cp .env.example .env
cd contracts && forge install && forge test
```

## Networks

- Dev: Celo Sepolia — `https://forno.celo-sepolia.celo-testnet.org/`
- Prod: Celo Mainnet — `https://forno.celo.org`
- cUSD: `0x765DE816845861e75A25fCA122bb6898B8B1282a`

## License

MIT
