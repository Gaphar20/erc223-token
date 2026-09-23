// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC223Token} from "../src/ERC223Token.sol";

/// @notice Minimal deployment script.
///         Run with:
///           forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast
///
/// @dev    No private keys or RPC URLs are committed to this file.
///         Supply them via environment variables or the --private-key flag.
contract Deploy is Script {
    function run() external returns (ERC223Token token) {
        // Read deployer from forge's vm.envUint / keystore — never hardcoded.
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        uint256 initialSupply = 1_000_000 * 10 ** 18; // 1 million tokens

        vm.startBroadcast(deployerKey);

        token = new ERC223Token(
            "Web3Bridge Token", // name
            "W3B", // symbol
            18, // decimals
            initialSupply // total supply → deployer
        );

        vm.stopBroadcast();

        console.log("ERC223Token deployed at:", address(token));
        console.log("Deployer:               ", deployer);
        console.log("Total supply:           ", initialSupply);
    }
}
