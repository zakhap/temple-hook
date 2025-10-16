// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";
import {T3MPL3Token} from "../src/T3MPL3Token.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

/**
 * @title LiveIntegrationTest
 * @notice Tests SimpleTempleHook against live deployments on anvil
 * @dev Use with: forge test --match-contract LiveIntegrationTest --rpc-url http://localhost:8545 -vv
 * 
 * Prerequisites:
 * 1. Start anvil: anvil --accounts 10 --balance 1000 --block-time 2
 * 2. Deploy contracts: forge script script/SimpleDeployment.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
 * 3. Run tests: forge test --match-contract LiveIntegrationTest --rpc-url http://localhost:8545 -vv
 */
contract LiveIntegrationTest is Test {
    // Update these addresses after deployment
    address constant POOL_MANAGER = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant SIMPLE_TEMPLE_HOOK = 0x5a2C959bf7c81c33AD97c0345aB3b15c8fEF5B8c;
    address constant T3MPL3_TOKEN = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
    address constant WETH_TOKEN = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
    address constant SWAP_ROUTER = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    
    // Test addresses from anvil
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address constant USER1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant QUBIT_CHARITY = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    
    SimpleTempleHook hook;
    T3MPL3Token t3mpl3Token;
    MockERC20 weth;
    PoolSwapTest swapRouter;
    
    function setUp() public {
        // Connect to live contracts
        hook = SimpleTempleHook(SIMPLE_TEMPLE_HOOK);
        t3mpl3Token = T3MPL3Token(T3MPL3_TOKEN);
        weth = MockERC20(WETH_TOKEN);
        swapRouter = PoolSwapTest(SWAP_ROUTER);
        
        // Verify contracts are deployed
        require(address(hook).code.length > 0, "Hook not deployed");
        require(address(t3mpl3Token).code.length > 0, "T3MPL3Token not deployed");
        require(address(weth).code.length > 0, "WETH not deployed");
    }
    
    function testLiveHookConfiguration() public {
        console.log("=== Testing Live Hook Configuration ===");
        
        // Test hook basic configuration
        uint256 donationPercentage = hook.getHookDonationPercentage();
        uint256 denominator = hook.getDonationDenominator();
        address qubitAddress = hook.qubitAddress();
        address donationManager = hook.getDonationManager();
        
        console.log("Donation percentage:", donationPercentage);
        console.log("Denominator:", denominator);
        console.log("QUBIT address:", qubitAddress);
        console.log("Donation manager:", donationManager);
        
        assertEq(denominator, 100000, "Donation denominator should be 100000");
        assertEq(qubitAddress, QUBIT_CHARITY, "QUBIT address should match");
        assertEq(donationManager, DEPLOYER, "Donation manager should be deployer");
    }
    
    function testLiveTokenBalances() public {
        console.log("=== Testing Live Token Balances ===");
        
        uint256 deployerT3MPL3 = t3mpl3Token.balanceOf(DEPLOYER);
        uint256 deployerWETH = weth.balanceOf(DEPLOYER);
        uint256 qubitWETH = weth.balanceOf(QUBIT_CHARITY);
        
        console.log("Deployer T3MPL3 balance:", deployerT3MPL3);
        console.log("Deployer WETH balance:", deployerWETH);
        console.log("QUBIT WETH balance:", qubitWETH);
        
        assertGt(deployerT3MPL3, 0, "Deployer should have T3MPL3 tokens");
    }
    
    function testLiveDonationPercentageUpdate() public {
        console.log("=== Testing Live Donation Percentage Update ===");
        
        vm.startPrank(DEPLOYER);
        
        uint256 initialPercentage = hook.getHookDonationPercentage();
        console.log("Initial percentage:", initialPercentage);
        
        // Update to 0.5%
        uint256 newPercentage = 500; // 0.5%
        hook.setDonationPercentage(newPercentage);
        
        uint256 updatedPercentage = hook.getHookDonationPercentage();
        console.log("Updated percentage:", updatedPercentage);
        
        assertEq(updatedPercentage, newPercentage, "Donation percentage should be updated");
        
        // Reset to original
        hook.setDonationPercentage(initialPercentage);
        
        vm.stopPrank();
    }
    
    function testLiveUnauthorizedAccess() public {
        console.log("=== Testing Live Unauthorized Access ===");
        
        vm.startPrank(USER1);
        
        // Should fail: non-manager trying to update percentage
        vm.expectRevert("Only donation manager");
        hook.setDonationPercentage(1000);
        
        // Should fail: non-manager trying to transfer role
        vm.expectRevert("Only donation manager");
        hook.setDonationManager(USER1);
        
        vm.stopPrank();
        
        console.log("Security controls working correctly");
    }
    
    function testLiveDonationCapEnforcement() public {
        console.log("=== Testing Live Donation Cap Enforcement ===");
        
        vm.startPrank(DEPLOYER);
        
        // Should fail: over 3% cap
        vm.expectRevert("Donation too high");
        hook.setDonationPercentage(3001);
        
        // Should succeed: exactly at cap
        hook.setDonationPercentage(3000);
        assertEq(hook.getHookDonationPercentage(), 3000, "Should accept 3% donation");
        
        // Reset to reasonable amount
        hook.setDonationPercentage(100); // 0.1%
        
        vm.stopPrank();
        
        console.log("Donation cap enforcement working correctly");
    }
    
    function testLiveTokenTransfers() public {
        console.log("=== Testing Live Token Transfers ===");
        
        vm.startPrank(DEPLOYER);
        
        uint256 transferAmount = 1000 ether;
        uint256 initialBalance = t3mpl3Token.balanceOf(USER1);
        
        // Transfer tokens to USER1
        t3mpl3Token.transfer(USER1, transferAmount);
        
        uint256 finalBalance = t3mpl3Token.balanceOf(USER1);
        
        console.log("Initial USER1 balance:", initialBalance);
        console.log("Transfer amount:", transferAmount);
        console.log("Final USER1 balance:", finalBalance);
        
        assertEq(finalBalance - initialBalance, transferAmount, "Transfer should work correctly");
        
        vm.stopPrank();
    }
    
    function testLiveEventEmission() public {
        console.log("=== Testing Live Event Emission ===");
        
        vm.startPrank(DEPLOYER);
        
        uint256 newPercentage = 250; // 0.25%
        
        // Record the event
        vm.recordLogs();
        hook.setDonationPercentage(newPercentage);
        
        // Get emitted events
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DonationPercentageUpdated(uint256)")) {
                eventFound = true;
                uint256 emittedPercentage = abi.decode(logs[i].data, (uint256));
                assertEq(emittedPercentage, newPercentage, "Event should emit correct percentage");
                console.log("DonationPercentageUpdated event emitted with value:", emittedPercentage);
                break;
            }
        }
        
        assertTrue(eventFound, "DonationPercentageUpdated event should be emitted");
        
        vm.stopPrank();
    }
    
    function testLiveManagerTransfer() public {
        console.log("=== Testing Live Manager Transfer ===");
        
        vm.startPrank(DEPLOYER);
        
        address originalManager = hook.getDonationManager();
        address newManager = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // anvil account 3
        
        // Record the event
        vm.recordLogs();
        hook.setDonationManager(newManager);
        
        // Verify transfer
        assertEq(hook.getDonationManager(), newManager, "Manager should be transferred");
        
        // Verify event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("DonationManagerUpdated(address)")) {
                eventFound = true;
                break;
            }
        }
        assertTrue(eventFound, "DonationManagerUpdated event should be emitted");
        
        // Transfer back
        vm.stopPrank();
        vm.startPrank(newManager);
        hook.setDonationManager(originalManager);
        vm.stopPrank();
        
        assertEq(hook.getDonationManager(), originalManager, "Manager should be transferred back");
        
        console.log("Manager transfer working correctly");
    }
}