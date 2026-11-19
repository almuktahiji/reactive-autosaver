// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AutoSaverVault } from "../src/AutoSaverVault.sol";

/// @notice Deploys AutoSaverVault on Base Sepolia.
/// @dev Run: TOKEN_ADDRESS=0x... REACTIVE_ADDRESS=0x... forge script
///      script/DeployVault.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
contract DeployVault is Script {
    /// @notice Base Sepolia callback proxy (Reactive docs, verified).
    address internal constant BASE_SEPOLIA_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    function run() external returns (AutoSaverVault vault) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address token = vm.envAddress("TOKEN_ADDRESS");
        address reactive = vm.envAddress("REACTIVE_ADDRESS");
        vm.startBroadcast(pk);
        vault = new AutoSaverVault(token, IPayable(payable(BASE_SEPOLIA_PROXY)), reactive);
        vm.stopBroadcast();
        console.log("AutoSaverVault:", address(vault));
        console.log("Token:", token);
        console.log("CallbackSender (RSC):", reactive);
    }
}
