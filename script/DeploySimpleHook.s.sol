// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Constants} from "./base/Constants.sol";
import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";

/// @notice Deploys SimpleTempleHook with proper address mining
contract DeploySimpleHookScript is Script, Constants {
    function run() external {
        console.log("=== DEPLOYING SIMPLE TEMPLE HOOK ===");
        console.log("Deployer:", msg.sender);

        // Get charity address from environment or use test address
        address charity;
        try vm.envAddress("CHARITY_ADDRESS") returns (address addr) {
            charity = addr;
            console.log("Using charity address from env:", charity);
        } catch {
            charity = makeAddr("charity");
            console.log("WARNING: Using test charity address:", charity);
            console.log("Set CHARITY_ADDRESS in .env for production!");
        }

        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        console.log("Mining hook address with flags:", flags);

        // Set donation manager to deployer wallet (not CREATE2 deployer!)
        address manager = 0x2226aE701ecf96E27373e896f3ddbe8a9A676A30;

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            POOLMANAGER,
            charity,
            manager
        );

        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(SimpleTempleHook).creationCode,
            constructorArgs
        );

        console.log("Hook will be deployed to:", hookAddress);
        console.log("Using salt:", vm.toString(salt));

        vm.startBroadcast();

        // Deploy the hook using CREATE2
        SimpleTempleHook hook = new SimpleTempleHook{salt: salt}(
            IPoolManager(POOLMANAGER),
            charity,
            manager
        );

        vm.stopBroadcast();

        require(address(hook) == hookAddress, "Hook address mismatch");

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("SimpleTempleHook deployed at:", address(hook));
        console.log("Charity address:", hook.charityAddress());
        console.log("Charity EIN:", hook.qubitEIN());
        console.log("Donation manager:", hook.getDonationManager());
        console.log("Donation percentage:", hook.getHookDonationPercentage(), "/ 100000");
        console.log("Donation denominator:", hook.getDonationDenominator());

        console.log("\n=== GOVERNANCE INFO ===");
        console.log("Donation manager can update:");
        console.log("  - Charity address (via setCharityAddress)");
        console.log("  - Donation percentage (via setDonationPercentage)");
        console.log("  - Manager role (via setDonationManager)");

        console.log("\n=== HOOK READY FOR POOL CREATION ===");
        console.log("Export this address:");
        console.log("export SIMPLE_HOOK_ADDRESS=", address(hook));
        console.log("export HOOK_ADDRESS=", address(hook));
    }
}
