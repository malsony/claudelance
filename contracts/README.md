# `contracts/`

Foundry workspace for `ClaudelanceCore.sol` — the single immutable contract behind the [Claudelance](../README.md) bounty marketplace.

[![Mainnet](https://img.shields.io/badge/Celo%20Mainnet-LIVE-brightgreen)](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5#code)
[![Solidity](https://img.shields.io/badge/solidity-0.8.24-363636)](https://docs.soliditylang.org)
[![OpenZeppelin v5](https://img.shields.io/badge/OpenZeppelin-v5-4E5EE4)](https://www.openzeppelin.com/contracts)
[![Coverage](https://img.shields.io/badge/lines-98.45%25-brightgreen)](#audit-posture)
[![Branches](https://img.shields.io/badge/branches-100%25-brightgreen)](#audit-posture)
[![Slither](https://img.shields.io/badge/slither-0%20findings-brightgreen)](#audit-posture)

## Layout

```
contracts/
├── src/
│   ├── ClaudelanceCore.sol            single immutable contract (Ownable2Step, Pausable, ReentrancyGuard)
│   ├── interfaces/IClaudelanceCore.sol
│   └── mocks/MockCUSD.sol             Sepolia stand-in — never deploy to mainnet
├── test/
│   ├── ClaudelanceCore.t.sol          67 unit tests
│   ├── invariant/                     4 invariants × 128k transitions each
│   └── integration/SepoliaLive.t.sol  28 fork tests vs live Sepolia bytecode
├── script/
│   ├── Deploy.s.sol                   distinct-keys-enforced mainnet broadcast
│   ├── DeployMockCUSD.s.sol           testnet cUSD stand-in
│   ├── SeedBounties.s.sol             15 seed bounties for dogfooding
│   ├── IntegrationE2E.s.sol           single-bounty E2E broadcast
│   ├── IntegrationResolveBatch.s.sol  resolve-batch broadcast (forfeit + alt-winner)
│   └── IntegrationFullFlow.s.sol      27-tx end-to-end against the post-PR-11 ABI
└── deployments/
    ├── celo-mainnet.json              source of truth for chain 42220
    └── celo-sepolia.json              source of truth for chain 11142220
```

## Audit posture

| Check | Result |
|---|---|
| Foundry unit tests | **67/67 pass** |
| Foundry invariant suite (256 runs × 500 calls = 128k transitions / invariant) | **4/4 pass, 0 reverts** |
| Foundry fork tests against live Sepolia | **28/28 pass** |
| Line coverage on `ClaudelanceCore.sol` | **98.45%** |
| Branch coverage | **100%** |
| Statement coverage | **99.16%** |
| Slither (filtered known-safe categories) | **0 findings** |
| Gas — `pickWinner` poster hot path | **136,505** |
| Gas — `settleStake` per worker | ~52,000 |
| Gas — `postBounty` | ~360,000 |

Invariants covered:

- **I1 value conservation** — `cUSD.balanceOf(core) == deposits − withdrawals`
- **I2 solvency** — `cUSD.balanceOf(core) ≥ Σ earnings`
- **I3 structural** — `totalBountiesResolved ≤ bountyCount`
- **I4 monotonic revenue** — `totalProtocolRevenue` never regresses

## Contract surface

`ClaudelanceCore` is a single immutable contract — `ReentrancyGuard + Ownable2Step + Pausable`. Surface by role:

| Role | Functions |
|------|-----------|
| Poster | `postBounty`, `pickWinner`, `cancelExpired` |
| Worker | `claimSlot`, `submitPR`, `withdrawEarnings` |
| Anyone (post-resolution) | `settleStake(bountyId, worker)` — permissionless pull pattern |
| Relayer | `attestCI` |
| Owner (2-day timelock + 14-day validity window) | `proposeTreasury`, `applyTreasury`, `cancelPendingTreasury`, `proposeCIRelayer`, `applyCIRelayer`, `cancelPendingCIRelayer`, `pause`, `unpause`, `rescueERC20` |

Constants:

| Name | Value |
|------|-------|
| `PROTOCOL_FEE_BPS` | 200 (2%) |
| `MAX_SLOTS` | 20 |
| `MIN_DEADLINE` | 1 day |
| `MAX_DEADLINE` | 14 days |
| `MIN_BOUNTY` | 0.5e18 cUSD |
| `RESOLUTION_GRACE_PERIOD` | 3 days |
| `ADMIN_TIMELOCK` | 2 days |
| `PROPOSAL_VALIDITY_WINDOW` | 14 days |

## Live deployments

| Network | Address | Verified |
|---------|---------|----------|
| Celo Mainnet (42220) | [`0x775d4278Ad3f5695fbab3c3313175e9D85811AB5`](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5) | [Celoscan source](https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5#code) |
| Celo Sepolia (11142220) | [`0xA2cAe817311BBF725a7eAa45aD533b89396dFfd8`](https://sepolia.celoscan.io/address/0xa2cae817311bbf725a7eaa45ad533b89396dffd8) | [Celoscan source](https://sepolia.celoscan.io/address/0xa2cae817311bbf725a7eaa45ad533b89396dffd8#code) |

Always read addresses from `deployments/celo-{mainnet,sepolia}.json`. Never hardcode.

## Quick start

```bash
# from contracts/
forge install                                          # pull OZ + forge-std
forge test                                             # 67 unit + 4 invariant
forge test --match-path "test/integration/*"           # +28 fork tests (needs CELO_SEPOLIA_RPC)
forge coverage --ir-minimum --no-match-coverage "script/|test/"
forge fmt                                              # canonical formatting
```

Slither (one-time install):

```bash
pip install slither-analyzer
slither src/ClaudelanceCore.sol \
  --solc-remaps "@openzeppelin/=lib/openzeppelin-contracts/" \
  --filter-paths "lib/" \
  --exclude timestamp,unindexed-event-address,uninitialized-local
```

The three excluded categories are reviewed in PR #9 — day-scale timestamps (safe at the granularity used), default-zero locals (intentional), and OZ `Pausable` indexing (out-of-scope third-party).

## Deploying

### Mainnet — chainid 42220, enforces distinct keys

```bash
source .env  # must contain MAINNET_DEPLOYER_PRIVATE_KEY + MAINNET_{OWNER,TREASURY,RELAYER}_ADDRESS

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

`Deploy.s.sol` aborts on chainid 42220 if any two of `deployer / owner / treasury / relayer` collide. The `ALLOW_SHARED_ADMIN_WALLETS` flag has no effect on mainnet.

### Sepolia — chainid 11142220, shared keys allowed via opt-in

```bash
# 1. Deploy a cUSD stand-in (once per chain):
forge script script/DeployMockCUSD.s.sol \
  --rpc-url $CELO_SEPOLIA_RPC --broadcast --private-key $DEPLOYER_PRIVATE_KEY

# 2. Deploy the core:
ALLOW_SHARED_ADMIN_WALLETS=true \
forge script script/Deploy.s.sol \
  --rpc-url $CELO_SEPOLIA_RPC --broadcast --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --private-key $DEPLOYER_PRIVATE_KEY
```

Get a unified [Etherscan API V2 key](https://etherscan.io/myapikey) — it works for Celo plus 60+ other EVM chains.

## Owner operations on mainnet

Owner is a [Safe multisig on Celo](https://app.safe.global/home?safe=celo:0xe9Fc48f315fD4E989637fAcC29AaF2717E19f7F0). All admin actions (`pause`, `proposeTreasury`, `proposeCIRelayer`, `cancelPending*`, `applyX`, `rescueERC20`) go through the Safe app — not the CLI.

Two-step rotation pattern with timelock:

1. **Propose** via Safe → `proposeTreasury(newAddr)` or `proposeCIRelayer(newAddr)`. Emits a `*Proposed` event with `effectiveAt = block.timestamp + 2 days`.
2. Wait the timelock. Anyone (not just the owner) can then call `applyTreasury()` / `applyCIRelayer()` once `effectiveAt` is reached, **as long as we are still within the 14-day validity window**.
3. **Cancel** at any time before apply via Safe → `cancelPendingTreasury()` / `cancelPendingCIRelayer()`.

If a proposal sits unapplied beyond `effectiveAt + 14 days`, it expires (`ProposalExpired`) and the owner must `proposeX` again.

## License

MIT — see repo root [LICENSE](../LICENSE).
