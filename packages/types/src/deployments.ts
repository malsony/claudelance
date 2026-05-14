/**
 * Live Claudelance deployment records per network.
 *
 * Source of truth lives in `contracts/deployments/celo-{mainnet,sepolia}.json`
 * within the monorepo; this module mirrors those records for npm consumers
 * who don't have access to the contracts workspace.
 */
export type Deployment = {
  /** EVM chain id. */
  chainId: number;
  /** Human-readable chain name. */
  chainName: string;
  /** ClaudelanceCore contract address. */
  core: `0x${string}`;
  /** cUSD ERC20 used by this deployment. */
  cUSD: `0x${string}`;
  /** Owner address (EOA, multisig, or governance contract). */
  owner: `0x${string}`;
  /** Treasury — collects 2% protocol fee + forfeited stakes via pull pattern. */
  treasury: `0x${string}`;
  /** Relayer that signs `attestCI` calls. */
  ciRelayer: `0x${string}`;
  /** Explorer URL for the core contract (verified source page). */
  explorerUrl: string;
};

export const MAINNET: Deployment = {
  chainId: 42220,
  chainName: 'celo-mainnet',
  core: '0x775d4278Ad3f5695fbab3c3313175e9D85811AB5',
  cUSD: '0x765DE816845861e75A25fCA122bb6898B8B1282a',
  owner: '0xe9Fc48f315fD4E989637fAcC29AaF2717E19f7F0',
  treasury: '0xCC0cCac212999612BdDdEb607B33CC1a46F8A401',
  ciRelayer: '0x1fEDda23c2945D59f3929e6C463cF685aC077ad5',
  explorerUrl: 'https://celoscan.io/address/0x775d4278ad3f5695fbab3c3313175e9d85811ab5#code',
};

export const SEPOLIA: Deployment = {
  chainId: 11142220,
  chainName: 'celo-sepolia',
  core: '0xA2cAe817311BBF725a7eAa45aD533b89396dFfd8',
  // MockCUSD stand-in — canonical cUSD does not exist on Celo Sepolia.
  cUSD: '0x207D662337694796E76a4d5577DC72C93Cd92822',
  owner: '0x987e2ed458ddAF6f900362F94558378056dCc226',
  treasury: '0x987e2ed458ddAF6f900362F94558378056dCc226',
  ciRelayer: '0x987e2ed458ddAF6f900362F94558378056dCc226',
  explorerUrl: 'https://sepolia.celoscan.io/address/0xa2cae817311bbf725a7eaa45ad533b89396dffd8#code',
};

/**
 * Lookup a deployment by chain id. Returns `undefined` for unknown chains so
 * consumers can fall back gracefully (multi-chain dapps, dev workflows on
 * forks, etc.).
 */
export function deploymentByChainId(chainId: number): Deployment | undefined {
  if (chainId === MAINNET.chainId) return MAINNET;
  if (chainId === SEPOLIA.chainId) return SEPOLIA;
  return undefined;
}
