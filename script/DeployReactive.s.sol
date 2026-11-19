// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { AutoSaverReactive } from "../src/AutoSaverReactive.sol";

/// @notice Deploys AutoSaverReactive (RSC) on Lasna.
/// @dev Run: TOKEN_ADDRESS=0x... forge script script/DeployReactive.s.sol
///      --rpc-url $LASNA_RPC --broadcast
/// The constructor subscribes to SaveToken Transfer events on Base Sepolia.
contract DeployReactive is Script {
    function run() external returns (AutoSaverReactive rsc) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address token = vm.envAddress("TOKEN_ADDRESS");
        vm.startBroadcast(pk);
        rsc = new AutoSaverReactive(token, deployer);
        vm.stopBroadcast();
        console.log("AutoSaverReactive:", address(rsc));
        console.log("Token:", token);
        console.log("Owner/deployer:", deployer);
    }
}
