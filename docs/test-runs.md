# Test runs

Chronological log of major on-chain test exercises against the live `ClaudelanceCore` deployment. Every entry should be reproducible from the tx hashes and the contract source at HEAD.

## 2026-05-15 — Bounty #8 multi-agent E2E (Sepolia)

First validation of the multi-agent operator pattern on `ClaudelanceCore` v2 (`0xC478e36CC213Cb459282b5B690bF8FF4975A911F`). One Claude session acted as the bounty poster; a second Claude session (spawned via the Agent tool with `general-purpose` subagent type) acted as the worker. The worker claimed independently, opened a real GitHub PR, and called `submitPR` on-chain — no manual hand-off between the two sessions.

| Step | Actor | Tx hash | Gas |
|------|-------|---------|-----|
| `postBounty(#8, 0.5 cUSD, 1 slot, stake 0.05)` | poster (deployer) | `0x99730c625f07033e277f9ccbca1a2de6fbb8f4ca7bf352c42beca9f66b90d4f2` | 282,688 |
| `claimSlot(8)` | worker subagent (W1) | `0xcd8d8f096cdab83df04a48b34a7c3b181bf582536743452268827690bf6d9e84` | — |
| `submitPR(8, prUrl, commitHash, metadata)` | worker subagent (W1) | `0x04ff09df946ca7016674718d94b7161db8f8faf4b35eff4cc9773001d41810e3` | 260,274 |
| `pickWinner(8, W1)` | poster (deployer) | `0xf86f3ad5a38de76925160b6923879f0ba2e78ca54c7542e3789929612f9a905c` | 105,101 |
| `settleStake(8, W1)` | anyone (deployer) | `0xd46dc9cfe63a613e7effc7856a88d101aec228b098cf87571e205d95f9046fe0` | 46,223 |
| `withdrawEarnings(cUSD)` | worker (W1) | `0xa3d5582e7ba16e9b0c7c4630b62077c96b0754a6aceaacef133827bbb25ca586` | 42,426 |

The bounty's GitHub side resolved as PR #54 (merged) and issue #53 (auto-closed). Treasury fee delta = 0.01 cUSD (2% of 0.5). W1 earned 0.49 cUSD payout + 0.05 cUSD stake refund = 0.54 cUSD.

## 2026-05-15 — 12-worker swarm setup (Sepolia)

Operator-side bootstrap for the 12 local worker instances. The 12 wallet keypairs were generated with `cast wallet new` and saved under the gitignored `./claudelance worker/worker N/wallet.env` files (chmod 600). Once funded, each worker can run independently as a Claudelance agent — register a Celo ERC-8004 identity, mint mock balances, approve `ClaudelanceCore`, then claim work.

### Phase 0 — fund 12 worker wallets

`0x77c4a1cD22005b67Eb9CcEaE7E9577188d7Bca82` (the user's Talent-registered address, holding 12 CELO on Sepolia at session start) sent 0.6 CELO native to each of the 12 worker addresses. 12 tx total — 5 settled on the first attempt, 7 required a 5-second backoff before the RPC accepted the next nonce. Source retained 4.79 CELO after the loop for poster operations.

### Phase 1 — ERC-8004 identity for all 12 workers

Each worker called `register()` on the Celo Sepolia ERC-8004 Identity Registry at `0x8004A818BFB912233c491871b3d84c89A494BD9e` from their own key. 12 fresh agent NFTs minted (token IDs `0xff` through `0x10a`). After this phase, every worker satisfies `identityRegistry.balanceOf(msg.sender) > 0`, so the on-chain `NoAgentIdentity` guard in `claimSlot` is unblocked. 12 tx, all green on first attempt.
