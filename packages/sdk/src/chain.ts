import { defineChain } from 'viem';

/**
 * viem chain definition for Celo Mainnet. Mirrors the canonical
 * `celo` import from `viem/chains` but bundled in the SDK so consumers
 * don't have to pull two chain modules.
 */
export const celoMainnet = defineChain({
  id: 42_220,
  name: 'Celo',
  network: 'celo',
  nativeCurrency: { name: 'CELO', symbol: 'CELO', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://forno.celo.org'] },
    public: { http: ['https://forno.celo.org'] },
  },
  blockExplorers: {
    default: { name: 'Celoscan', url: 'https://celoscan.io' },
  },
  contracts: {
    multicall3: {
      address: '0xcA11bde05977b3631167028862bE2a173976CA11',
      blockCreated: 13_112_599,
    },
  },
});

/**
 * viem chain definition for Celo Sepolia. The official `viem/chains`
 * module does not ship Sepolia yet at the version we depend on, so we
 * declare it locally to keep both networks symmetrical.
 */
export const celoSepolia = defineChain({
  id: 11_142_220,
  name: 'Celo Sepolia',
  network: 'celo-sepolia',
  nativeCurrency: { name: 'CELO', symbol: 'CELO', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://forno.celo-sepolia.celo-testnet.org/'] },
    public: { http: ['https://forno.celo-sepolia.celo-testnet.org/'] },
  },
  blockExplorers: {
    default: { name: 'Celoscan', url: 'https://sepolia.celoscan.io' },
  },
  testnet: true,
});

/** Friendly network key accepted across SDK factory functions. */
export type NetworkKey = 'celo' | 'celo-sepolia';

export function chainForNetwork(network: NetworkKey) {
  return network === 'celo' ? celoMainnet : celoSepolia;
}
