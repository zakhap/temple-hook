// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";
import {T3MPL3Token} from "../src/T3MPL3Token.sol";

contract T3MPL3Test is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    SimpleTempleHook hook;
    T3MPL3Token t3mpl3Token;
    MockERC20 weth;
    PoolId poolId;
    PoolKey poolKey;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    // Test addresses
    address alice = address(0x1);
    address bob = address(0x2);
    address qubitAddress;

    function setUp() public {
        // Deploy manager, routers, and test infrastructure
        deployFreshManagerAndRouters();

        // Deploy T3MPL3 Token
        t3mpl3Token = new T3MPL3Token();
        
        // Deploy mock WETH for testing
        weth = new MockERC20("Wrapped Ether", "WETH", 18);

        // Deploy the SimpleTempleHook to an address with correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG) ^ (0x4444 << 144) // Namespace to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("SimpleTempleHook.sol:SimpleTempleHook", constructorArgs, flags);
        hook = SimpleTempleHook(flags);

        qubitAddress = hook.qubitAddress();

        // Determine token order for pool (ensure weth < t3mpl3Token for currency0 < currency1)
        Currency currency0;
        Currency currency1;
        if (address(weth) < address(t3mpl3Token)) {
            currency0 = Currency.wrap(address(weth));
            currency1 = Currency.wrap(address(t3mpl3Token));
        } else {
            currency0 = Currency.wrap(address(t3mpl3Token));
            currency1 = Currency.wrap(address(weth));
        }

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Mint tokens to test users
        weth.mint(address(this), 1000 ether);
        weth.mint(alice, 100 ether);
        weth.mint(bob, 100 ether);
        
        // T3MPL3 tokens already minted to deployer in constructor
        t3mpl3Token.transfer(alice, 100_000 ether);
        t3mpl3Token.transfer(bob, 100_000 ether);

        // Add initial liquidity
        weth.approve(address(modifyLiquidityRouter), type(uint256).max);
        t3mpl3Token.approve(address(modifyLiquidityRouter), type(uint256).max);

        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 100e18,
            salt: 0
        });

        modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        // Approve tokens for swap router (simpler approach)
        weth.approve(address(swapRouter), type(uint256).max);
        t3mpl3Token.approve(address(swapRouter), type(uint256).max);

        vm.startPrank(alice);
        weth.approve(address(swapRouter), type(uint256).max);
        t3mpl3Token.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        weth.approve(address(swapRouter), type(uint256).max);
        t3mpl3Token.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    function testHookTakesDonationOnSwap() public {
        uint256 swapAmount = 1 ether;
        uint256 expectedDonation = (swapAmount * hook.getHookDonationPercentage()) / hook.getDonationDenominator();
        
        // Record initial balances
        uint256 qubitInitialBalance = weth.balanceOf(qubitAddress);
        uint256 aliceInitialWeth = weth.balanceOf(alice);

        // Perform swap as Alice
        vm.prank(alice);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        BalanceDelta swapDelta = swap(poolKey, zeroForOne, int256(swapAmount), abi.encode(alice));

        // Check that donation was taken
        uint256 qubitFinalBalance = weth.balanceOf(qubitAddress);
        assertEq(qubitFinalBalance - qubitInitialBalance, expectedDonation, "Donation amount incorrect");

        // Check that Alice's balance decreased by more than the swap amount (swap + donation)
        uint256 aliceFinalWeth = weth.balanceOf(alice);
        assertGt(aliceInitialWeth - aliceFinalWeth, swapAmount, "Alice should pay swap amount + donation");
    }

    function testDonationEventEmitted() public {
        uint256 swapAmount = 1 ether;
        uint256 expectedDonation = (swapAmount * hook.getHookDonationPercentage()) / hook.getDonationDenominator();
        Currency donationCurrency = Currency.unwrap(poolKey.currency0) == address(weth) ? poolKey.currency0 : poolKey.currency1;

        // Expect the donation event
        vm.expectEmit(true, true, true, true);
        emit SimpleTempleHook.CharitableDonationTaken(alice, poolId, donationCurrency, expectedDonation);

        // Perform swap
        vm.prank(alice);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        swap(poolKey, zeroForOne, int256(swapAmount), abi.encode(alice));
    }

    function testDifferentSwapDirections() public {
        uint256 swapAmount = 1 ether;
        
        // Test WETH -> T3MPL3 swap
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        uint256 qubitBalanceBefore = getQubitBalance(zeroForOne ? poolKey.currency0 : poolKey.currency1);
        
        vm.prank(alice);
        swap(poolKey, zeroForOne, int256(swapAmount), abi.encode(alice));
        
        uint256 qubitBalanceAfter = getQubitBalance(zeroForOne ? poolKey.currency0 : poolKey.currency1);
        uint256 expectedDonation = (swapAmount * hook.getHookDonationPercentage()) / hook.getDonationDenominator();
        assertEq(qubitBalanceAfter - qubitBalanceBefore, expectedDonation, "Donation incorrect for zeroForOne swap");

        // Test T3MPL3 -> WETH swap (opposite direction)
        bool oneForZero = !zeroForOne;
        qubitBalanceBefore = getQubitBalance(oneForZero ? poolKey.currency0 : poolKey.currency1);
        
        vm.prank(bob);
        swap(poolKey, oneForZero, int256(swapAmount), abi.encode(bob));
        
        qubitBalanceAfter = getQubitBalance(oneForZero ? poolKey.currency0 : poolKey.currency1);
        assertEq(qubitBalanceAfter - qubitBalanceBefore, expectedDonation, "Donation incorrect for oneForZero swap");
    }

    function testDonationPercentageUpdate() public {
        // Test initial percentage
        assertEq(hook.getHookDonationPercentage(), 10, "Initial donation percentage should be 10 (0.01%)");

        // Update to 1%
        uint256 newPercentage = 1000; // 1% = 1000/100000
        hook.setDonationPercentage(newPercentage);
        assertEq(hook.getHookDonationPercentage(), newPercentage, "Donation percentage not updated");

        // Test swap with new percentage
        uint256 swapAmount = 1 ether;
        uint256 expectedDonation = (swapAmount * newPercentage) / hook.getDonationDenominator();
        
        uint256 qubitBalanceBefore = weth.balanceOf(qubitAddress);
        
        vm.prank(alice);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        swap(poolKey, zeroForOne, int256(swapAmount), abi.encode(alice));
        
        uint256 qubitBalanceAfter = weth.balanceOf(qubitAddress);
        assertEq(qubitBalanceAfter - qubitBalanceBefore, expectedDonation, "Donation with updated percentage incorrect");
    }

    function testOnlyDonationManagerCanUpdatePercentage() public {
        vm.prank(alice);
        vm.expectRevert("Only donation manager");
        hook.setDonationPercentage(500);
    }

    function testDonationPercentageCap() public {
        vm.expectRevert("Donation too high");
        hook.setDonationPercentage(1001); // Over 1% cap
    }

    function testSmallSwapAmounts() public {
        uint256 smallSwapAmount = 0.001 ether; // Very small amount
        uint256 expectedDonation = (smallSwapAmount * hook.getHookDonationPercentage()) / hook.getDonationDenominator();
        
        uint256 qubitBalanceBefore = weth.balanceOf(qubitAddress);
        
        vm.prank(alice);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        swap(poolKey, zeroForOne, int256(smallSwapAmount), abi.encode(alice));
        
        uint256 qubitBalanceAfter = weth.balanceOf(qubitAddress);
        assertEq(qubitBalanceAfter - qubitBalanceBefore, expectedDonation, "Small donation amount incorrect");
    }

    function testLargeSwapAmounts() public {
        // Give Alice more tokens for large swap
        weth.mint(alice, 50 ether);
        
        uint256 largeSwapAmount = 50 ether;
        uint256 expectedDonation = (largeSwapAmount * hook.getHookDonationPercentage()) / hook.getDonationDenominator();
        
        uint256 qubitBalanceBefore = weth.balanceOf(qubitAddress);
        
        vm.prank(alice);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        swap(poolKey, zeroForOne, int256(largeSwapAmount), abi.encode(alice));
        
        uint256 qubitBalanceAfter = weth.balanceOf(qubitAddress);
        assertEq(qubitBalanceAfter - qubitBalanceBefore, expectedDonation, "Large donation amount incorrect");
    }

    function testMultipleSwapsAccumulateDonations() public {
        uint256 swapAmount = 1 ether;
        uint256 expectedDonationPerSwap = (swapAmount * hook.getHookDonationPercentage()) / hook.getDonationDenominator();
        
        uint256 qubitBalanceBefore = weth.balanceOf(qubitAddress);
        
        // Perform 3 swaps
        vm.startPrank(alice);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        swap(poolKey, zeroForOne, int256(swapAmount), abi.encode(alice));
        swap(poolKey, zeroForOne, int256(swapAmount), abi.encode(alice));
        swap(poolKey, zeroForOne, int256(swapAmount), abi.encode(alice));
        vm.stopPrank();
        
        uint256 qubitBalanceAfter = weth.balanceOf(qubitAddress);
        assertEq(qubitBalanceAfter - qubitBalanceBefore, expectedDonationPerSwap * 3, "Multiple donations not accumulated correctly");
    }

    function testDonationManagerTransfer() public {
        address newManager = address(0x999);
        
        // Transfer donation manager role
        hook.setDonationManager(newManager);
        assertEq(hook.getDonationManager(), newManager, "Donation manager not transferred");
        
        // Old manager should no longer be able to update percentage
        vm.expectRevert("Only donation manager");
        hook.setDonationPercentage(500);
        
        // New manager should be able to update percentage
        vm.prank(newManager);
        hook.setDonationPercentage(500);
        assertEq(hook.getHookDonationPercentage(), 500, "New manager cannot update percentage");
    }

    // Helper function to get QUBIT balance for the correct currency
    function getQubitBalance(Currency currency) internal view returns (uint256) {
        if (Currency.unwrap(currency) == address(weth)) {
            return weth.balanceOf(qubitAddress);
        } else {
            return t3mpl3Token.balanceOf(qubitAddress);
        }
    }
}
