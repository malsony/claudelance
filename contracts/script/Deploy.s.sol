// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { ClaudelanceCore } from "../src/ClaudelanceCore.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
    /// @dev Set ALLOW_SHARED_ADMIN_WALLETS=true to bypass the "distinct wallets"
    ///      guard. Intended only for ephemeral testnet smoke deploys; never set
    ///      this flag for mainnet broadcasts.
    function run() external returns (ClaudelanceCore core) {
        address cusd = vm.envAddress("CUSD_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address relayer = vm.envAddress("CI_RELAYER_ADDRESS");
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);
        bool allowShared = vm.envOr("ALLOW_SHARED_ADMIN_WALLETS", false);

        require(cusd != address(0), "CUSD_ADDRESS missing");
        require(treasury != address(0), "TREASURY_ADDRESS missing");
        require(relayer != address(0), "CI_RELAYER_ADDRESS missing");

        // Mainnet (chainid 42220) MUST use four distinct wallets so that a
        // single compromised key cannot drain or reroute the contract.
        bool isMainnet = block.chainid == 42_220;
        if (isMainnet || !allowShared) {
            address deployer = msg.sender;
            require(owner != treasury, "owner == treasury (separate keys required)");
            require(owner != relayer, "owner == relayer (separate keys required)");
            require(treasury != relayer, "treasury == relayer (separate keys required)");
            require(deployer != owner, "deployer == owner (use a separate ops key)");
            require(deployer != treasury, "deployer == treasury (use a separate ops key)");
            require(deployer != relayer, "deployer == relayer (use a separate ops key)");
        }

        vm.startBroadcast();
        core = new ClaudelanceCore(IERC20(cusd), treasury, relayer, owner);
        vm.stopBroadcast();

        console2.log("ClaudelanceCore deployed:", address(core));
        console2.log("  cUSD:    ", cusd);
        console2.log("  treasury:", treasury);
        console2.log("  relayer: ", relayer);
        console2.log("  owner:   ", owner);
        if (isMainnet) {
            console2.log("MAINNET DEPLOY -- verify owner is a multisig and rotate hot keys after launch");
        }

        _writeDeployment(address(core), cusd, treasury, relayer, owner);
    }

    function _writeDeployment(address core, address cusd, address treasury, address relayer, address owner)
        internal
    {
        string memory chain = _chainName();
        string memory path = string.concat("./deployments/", chain, ".json");
        string memory json = string.concat(
            "{\n",
            '  "chainId": ',
            vm.toString(block.chainid),
            ",\n",
            '  "core": "',
            vm.toString(core),
            '",\n',
            '  "cUSD": "',
            vm.toString(cusd),
            '",\n',
            '  "treasury": "',
            vm.toString(treasury),
            '",\n',
            '  "ciRelayer": "',
            vm.toString(relayer),
            '",\n',
            '  "owner": "',
            vm.toString(owner),
            '",\n',
            '  "deployedAt": ',
            vm.toString(block.timestamp),
            "\n}\n"
        );
        vm.writeFile(path, json);
        console2.log("wrote", path);
    }

    function _chainName() internal view returns (string memory) {
        if (block.chainid == 42_220) return "celo-mainnet";
        if (block.chainid == 11_142_220) return "celo-sepolia";
        return string.concat("chain-", vm.toString(block.chainid));
    }
}
