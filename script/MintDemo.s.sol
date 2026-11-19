// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { SaveToken } from "../src/SaveToken.sol";

/// @notice Mints demo SAVE to the demo user (owner-only, Base Sepolia).
/// @dev Run: TOKEN_ADDRESS=0x... DEMO_USER=0x... MINT_AMOUNT=10000
///      forge script script/MintDemo.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
/// MINT_AMOUNT is in whole SAVE (18 decimals are added here).
contract MintDemo is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address tokenAddr = vm.envAddress("TOKEN_ADDRESS");
        address demoUser = vm.envAddress("DEMO_USER");
        uint256 amountWhole = vm.envOr("MINT_AMOUNT", uint256(10_000));
        uint256 amount = amountWhole * 1 ether;

        vm.startBroadcast(pk);
        SaveToken(tokenAddr).mint(demoUser, amount);
        vm.stopBroadcast();

        console.log("SaveToken:", tokenAddr);
        console.log("Minted to:", demoUser);
        console.log("Amount (SAVE):", amountWhole);
    }
}
