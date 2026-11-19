// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { AutoSaverReactive } from "../src/AutoSaverReactive.sol";

/// @notice Wires the RSC to the vault and registers the demo user (Lasna).
/// @dev Run: REACTIVE_ADDRESS=0x... VAULT_ADDRESS=0x... DEMO_USER=0x...
///      SAVINGS_PCT=10 forge script script/Configure.s.sol
///      --rpc-url $LASNA_RPC --broadcast
contract Configure is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address rscAddr = vm.envAddress("REACTIVE_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address demoUser = vm.envAddress("DEMO_USER");
        uint256 pct = vm.envOr("SAVINGS_PCT", uint256(10));
        AutoSaverReactive rsc = AutoSaverReactive(payable(rscAddr));

        vm.startBroadcast(pk);
        rsc.setVault(vault);
        rsc.setSavingsPct(demoUser, pct);
        vm.stopBroadcast();

        console.log("RSC:", rscAddr);
        console.log("Vault set to:", vault);
        console.log("Demo user:", demoUser);
        console.log("Savings pct:", pct);
    }
}
