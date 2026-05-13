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
- cUSD (mainnet): `0x765DE816845861e75A25fCA122bb6898B8B1282a`
- cUSD on Sepolia: no canonical contract — use `script/DeployMockCUSD.s.sol` to deploy a stand-in.

## Live Sepolia deployment

| Contract | Address |
|----------|---------|
| ClaudelanceCore | [`0x8223cB87CfAAB9c1a5e524545C3097df1517191D`](https://celo-sepolia.blockscout.com/address/0x8223cB87CfAAB9c1a5e524545C3097df1517191D) |
| MockCUSD (stand-in) | [`0x207D662337694796E76a4d5577DC72C93Cd92822`](https://celo-sepolia.blockscout.com/address/0x207D662337694796E76a4d5577DC72C93Cd92822) |

Full deploy record: `contracts/deployments/celo-sepolia.json`.

## Deploying to a new network

```bash
cd contracts
cp .env.example .env   # then fill DEPLOYER_PRIVATE_KEY, TREASURY_ADDRESS, CI_RELAYER_ADDRESS

# 1. Testnet only — deploy a cUSD stand-in if the chain lacks one:
forge script script/DeployMockCUSD.s.sol \
  --rpc-url celo_sepolia --broadcast --private-key $DEPLOYER_PRIVATE_KEY

# 2. Set CUSD_ADDRESS to the value printed above, then:
forge script script/Deploy.s.sol \
  --rpc-url celo_sepolia --broadcast --private-key $DEPLOYER_PRIVATE_KEY

# 3. (Once CELOSCAN_API_KEY is set) post-hoc verify:
forge verify-contract --chain celo_sepolia <CORE_ADDRESS> \
  src/ClaudelanceCore.sol:ClaudelanceCore
```

For mainnet, skip step 1 and point `CUSD_ADDRESS` at `0x765DE816845861e75A25fCA122bb6898B8B1282a`.

## License

MIT
