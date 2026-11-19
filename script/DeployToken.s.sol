// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { SaveToken } from "../src/SaveToken.sol";

/// @notice Deploys SaveToken on Base Sepolia.
/// @dev Run: forge script script/DeployToken.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast
contract DeployToken is Script {
    function run() external returns (SaveToken token) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);
        token = new SaveToken(deployer);
        vm.stopBroadcast();
        console.log("SaveToken:", address(token));
        console.log("Owner/deployer:", deployer);
    }
}
