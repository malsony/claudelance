// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title  MockCUSD
/// @notice Testnet stand-in for Celo's cUSD. Used by Foundry tests and by the
///         Sepolia deploy pipeline, since canonical cUSD does not exist on
///         Celo Sepolia. Public `mint` is intentional — never deploy to
///         mainnet.
contract MockCUSD is ERC20 {
    constructor() ERC20("Mock Celo Dollar", "cUSD") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
