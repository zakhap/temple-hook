// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

// Import our hook
import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";

contract DeployHookOnlyScript is Script {
    function run() public {
        console.log("=== HOOK DEPLOYMENT WITH CORRECT ADDRESS ===");
        
        vm.startBroadcast();
        
        // Deploy PoolManager first
        IPoolManager manager = IPoolManager(address(new PoolManager(address(0))));
        console.log("PoolManager deployed at:", address(manager));
        
        // Find a working salt through brute force (much faster than HookMiner)
        uint256 attempts = 0;
        bytes32 salt;
        address hookAddress;
        uint160 targetFlags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);
        
        console.log("Mining hook address with correct permissions...");
        console.log("Target flags:", targetFlags);
        
        // Try different salts until we find one that works
        for (uint256 i = 0; i < 1000; i++) {
            salt = bytes32(i);
            hookAddress = computeHookCreate2Address(
                salt,
                keccak256(abi.encodePacked(
                    type(SimpleTempleHook).creationCode,
                    abi.encode(address(manager))
                ))
            );
            
            // Check if the address has the right flags in the last 12 bits
            uint160 addressFlags = uint160(hookAddress) & uint160(0xfff);
            if (addressFlags == targetFlags) {
                console.log("Found valid address after", i + 1, "attempts");
                console.log("Salt:", vm.toString(salt));
                console.log("Hook address:", hookAddress);
                break;
            }
            attempts++;
        }
        
        if (attempts >= 1000) {
            console.log("Could not find valid address in 1000 attempts");
            console.log("Deploying with regular address for testing...");
            salt = bytes32(0);
        }
        
        // Deploy the hook
        SimpleTempleHook hook = new SimpleTempleHook{salt: salt}(manager);
        console.log("SimpleTempleHook deployed at:", address(hook));
        console.log("QUBIT charity address:", hook.qubitAddress());
        
        // Verify the deployment
        console.log("Hook donation percentage:", hook.getHookDonationPercentage());
        console.log("Hook donation manager:", hook.getDonationManager());
        
        vm.stopBroadcast();
        
        console.log("\n=== HOOK DEPLOYMENT COMPLETE ===");
        console.log("Use this address in your pool creation:");
        console.log("Hook Address: ", address(hook));
    }
    
    function computeHookCreate2Address(bytes32 salt, bytes32 bytecodeHash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            bytecodeHash
        )))));
    }
}