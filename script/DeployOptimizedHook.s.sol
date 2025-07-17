// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Constants} from "./base/Constants.sol";
import {OptimizedTempleHook} from "../src/OptimizedTempleHook.sol";

/// @notice Deploys OptimizedTempleHook with proper address mining
contract DeployOptimizedHookScript is Script, Constants {
    function run() external {
        console.log("=== DEPLOYING OPTIMIZED TEMPLE HOOK ===");
        console.log("Deployer:", msg.sender);
        
        // Test addresses for local development
        address charity = makeAddr("charity");
        address donationManager = msg.sender; // Deployer is donation manager
        address guardian = makeAddr("guardian");
        
        console.log("Charity address:", charity);
        console.log("Donation manager:", donationManager);
        console.log("Guardian address:", guardian);
        
        // Hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | 
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | 
            Hooks.AFTER_SWAP_FLAG |
            Hooks.AFTER_INITIALIZE_FLAG
        );
        
        console.log("Mining hook address with flags:", flags);
        
        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(
            POOLMANAGER,
            charity,
            donationManager,
            guardian
        );
        
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER, 
            flags, 
            type(OptimizedTempleHook).creationCode, 
            constructorArgs
        );
        
        console.log("Hook will be deployed to:", hookAddress);
        console.log("Using salt:", vm.toString(salt));
        
        vm.startBroadcast();
        
        // Deploy the hook using CREATE2
        OptimizedTempleHook hook = new OptimizedTempleHook{salt: salt}(
            IPoolManager(POOLMANAGER),
            charity,
            donationManager,
            guardian
        );
        
        vm.stopBroadcast();
        
        require(address(hook) == hookAddress, "Hook address mismatch");
        
        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("OptimizedTempleHook deployed at:", address(hook));
        console.log("Charity address:", hook.CHARITY_ADDRESS());
        console.log("Donation manager:", hook.donationManager());
        console.log("Guardian:", hook.guardian());
        console.log("Emergency paused:", hook.emergencyPaused());
        console.log("Donation denominator:", hook.getDonationDenominator());
        
        console.log("\n=== HOOK READY FOR POOL CREATION ===");
    }
}