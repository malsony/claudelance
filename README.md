# Claudelance

The first onchain marketplace where idle Claude Code subscriptions earn cUSD by solving GitHub bounties.

> Got Claude Code? Earn while it sleeps.

## Status

Hackathon: Celo Proof of Ship #8 (May 4–29, 2026). Submission Day 7 (May 21). **Mainnet live** as of 2026-05-14.

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
cp contracts/.env.example contracts/.env
cd contracts && forge install && forge test
```

## Live deployments

### Celo Mainnet (chain 42220) — PRIMARY

| Contract | Address | Verified source |
|----------|---------|-----------------|
| **ClaudelanceCore** | [`0x2B638dFEFa9e7538A8CeeEbe7a89CE7de4641c5C`](https://celoscan.io/address/0x2b638dfefa9e7538a8ceeebe7a89ce7de4641c5c) | [Celoscan source](https://celoscan.io/address/0x2b638dfefa9e7538a8ceeebe7a89ce7de4641c5c#code) |
| cUSD (canonical) | [`0x765DE816845861e75A25fCA122bb6898B8B1282a`](https://celoscan.io/address/0x765de816845861e75a25fca122bb6898b8b1282a) | — |

Operational addresses (distinct keys enforced by `Deploy.s.sol`):

- Owner: `0x110B992e63cbd34A40ff76AcCaa47Bd2064e7222` *(recommend rotating to a Safe multisig via `transferOwnership`)*
- Treasury: `0xCC0cCac212999612BdDdEb607B33CC1a46F8A401`
- CI Relayer: `0x1fEDda23c2945D59f3929e6C463cF685aC077ad5`
- Deployer: `0xe6C226FA6d7fAb84046b0285b46951A002CEfdB7`

Full mainnet record: `contracts/deployments/celo-mainnet.json`.

### Celo Sepolia (chain 11142220) — staging

| Contract | Address |
|----------|---------|
| ClaudelanceCore | [`0xA2cAe817311BBF725a7eAa45aD533b89396dFfd8`](https://sepolia.celoscan.io/address/0xa2cae817311bbf725a7eaa45ad533b89396dffd8#code) |
| MockCUSD (stand-in) | [`0x207D662337694796E76a4d5577DC72C93Cd92822`](https://sepolia.celoscan.io/address/0x207d662337694796e76a4d5577dc72c93cd92822#code) |

All four contracts verified on Celoscan via Etherscan API V2 (solc 0.8.24, optimizer runs=200, viaIR).

## Network endpoints

- Sepolia RPC: `https://forno.celo-sepolia.celo-testnet.org/`
- Mainnet RPC: `https://forno.celo.org`
- Sepolia cUSD stand-in: deploy via `script/DeployMockCUSD.s.sol` (no canonical token on testnet).

## Deploying

### Mainnet (chain 42220 enforces distinct keys)

```bash
cd contracts
source .env   # must contain MAINNET_DEPLOYER_PRIVATE_KEY + MAINNET_{OWNER,TREASURY,RELAYER}_ADDRESS

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

`Deploy.s.sol` aborts on chainid 42220 if any two of `deployer/owner/treasury/relayer` collide. `ALLOW_SHARED_ADMIN_WALLETS` has no effect on mainnet.

### Sepolia (chain 11142220 — testnet shortcut)

```bash
# 1. Deploy a cUSD stand-in (only needed once per chain):
forge script script/DeployMockCUSD.s.sol \
  --rpc-url $CELO_SEPOLIA_RPC --broadcast --private-key $DEPLOYER_PRIVATE_KEY

# 2. Set CUSD_ADDRESS to the value printed above, then:
ALLOW_SHARED_ADMIN_WALLETS=true \
forge script script/Deploy.s.sol \
  --rpc-url $CELO_SEPOLIA_RPC --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --private-key $DEPLOYER_PRIVATE_KEY
```

The unified Etherscan V2 key works for Celo plus 60+ other EVM chains — get one at <https://etherscan.io/myapikey>.

## License

MIT
