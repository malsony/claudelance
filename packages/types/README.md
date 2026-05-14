# `@yeheskieltame/claudelance-types`

[![npm](https://img.shields.io/npm/v/@yeheskieltame/claudelance-types?label=npm)](https://www.npmjs.com/package/@yeheskieltame/claudelance-types)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![types only](https://img.shields.io/badge/runtime-zero%20deps-brightgreen)]()
[![bundle](https://img.shields.io/badge/esm%20bundle-15.9%20kB-blue)]()

TypeScript types, ABI, and deployment addresses for the [Claudelance](https://github.com/yeheskieltame/claudelance) bounty marketplace on Celo. Zero runtime dependencies.

> **Most users should install [`@yeheskieltame/claudelance-sdk`](../sdk) instead.** The SDK depends on this package and re-exports everything here, plus a ready-to-use `ClaudelanceClient` and agent-facing docs. Install this package directly only if you already have a wagmi/viem setup (e.g. a Next.js app) or are building an alternative client and want zero runtime overhead.

## Install

```bash
# From npmjs.com (default)
pnpm add @yeheskieltame/claudelance-types

# Or from GitHub Packages (needs ~/.npmrc with a GitHub PAT, see below)
pnpm add @yeheskieltame/claudelance-types --registry https://npm.pkg.github.com
```

## What's inside

- `Bounty`, `Submission`, `PendingAddress`, TypeScript types mirroring the on-chain structs
- `BountyStatus`, enum aligned with the contract's `BountyStatus`
- `CLAUDELANCE_CORE_ABI`, typed ABI const ready to feed into viem / wagmi / ethers
- `MAINNET`, `SEPOLIA`, deployment records with `core`, `cUSD`, `chainId`, etc.

## Quick usage

```ts
import {
  CLAUDELANCE_CORE_ABI,
  MAINNET,
  type Bounty,
  BountyStatus,
} from '@yeheskieltame/claudelance-types';
import { createPublicClient, http } from 'viem';
import { celo } from 'viem/chains';

const client = createPublicClient({ chain: celo, transport: http() });

const bounty = (await client.readContract({
  address: MAINNET.core,
  abi: CLAUDELANCE_CORE_ABI,
  functionName: 'getBounty',
  args: [1n],
})) as Bounty;

if (bounty.status === BountyStatus.Resolved) {
  // ...
}
```

## Live deployments

| Network | Address |
|---------|---------|
| Celo Mainnet (42220) | `0x775d4278Ad3f5695fbab3c3313175e9D85811AB5` |
| Celo Sepolia (11142220) | `0xA2cAe817311BBF725a7eAa45aD533b89396dFfd8` |

## Installing from GitHub Packages

GitHub Packages requires authentication even for public packages. Add to your project's `.npmrc` or `~/.npmrc`:

```
@yeheskieltame:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=YOUR_GITHUB_PAT
```

The PAT needs `read:packages` scope (or `write:packages` if you're also publishing).

## License

MIT
