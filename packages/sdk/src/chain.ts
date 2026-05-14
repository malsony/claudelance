import { defineChain } from 'viem';

/**
 * viem chain definition for Celo Mainnet. Exported for advanced users who
 * wire up their own client; the SDK factory only resolves Sepolia in v2.
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

/** Friendly network key accepted by SDK factories. v2 only ships Sepolia. */
export type NetworkKey = 'sepolia';

export function chainForNetwork(network: NetworkKey) {
  if (network !== 'sepolia') {
    throw new Error(`[chainForNetwork] Unknown network: ${network}`);
  }
  return celoSepolia;
}
