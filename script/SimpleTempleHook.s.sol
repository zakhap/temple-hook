// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Constants} from "./base/Constants.sol";
import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";

import {console} from "forge-std/console.sol";

/// @notice Mines the address and deploys the SimpleTempleHook.sol Hook contract
contract SimpleTempleHookScript is Script, Constants {
    function setUp() public {}

    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(SimpleTempleHook).creationCode, constructorArgs);
        console.log("Deploying SimpleTempleHook to:", hookAddress);
        
        // Deploy the hook using CREATE2
        vm.broadcast();
        SimpleTempleHook simpleTempleHook = new SimpleTempleHook{salt: salt}(IPoolManager(POOLMANAGER));
        require(address(simpleTempleHook) == hookAddress, "SimpleTempleHookScript: hook address mismatch");
        
        console.log("SimpleTempleHook deployed successfully!");
        console.log("Charity address set to:", simpleTempleHook.qubitAddress());
        console.log("Donation manager set to:", simpleTempleHook.getDonationManager());
        console.log("Initial donation percentage:", simpleTempleHook.getHookDonationPercentage());
    }
}