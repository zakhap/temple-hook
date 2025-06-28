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

contract T3MPL3SimpleTest is Test, Fixtures {
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
            uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144) // Namespace to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager);
        deployCodeTo("SimpleTempleHook.sol:SimpleTempleHook", constructorArgs, flags);
        hook = SimpleTempleHook(flags);

        qubitAddress = hook.qubitAddress();

        // Determine token order for pool (ensure proper ordering)
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

        // Mint tokens for liquidity and testing
        weth.mint(address(this), 1000 ether);
        weth.mint(alice, 100 ether);
        weth.mint(bob, 100 ether);
        
        // T3MPL3 tokens already minted to deployer in constructor
        t3mpl3Token.transfer(alice, 100_000 ether);
        t3mpl3Token.transfer(bob, 100_000 ether);

        // Provide initial liquidity using modifyLiquidity
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        // Approve tokens for modifyLiquidity
        weth.approve(address(modifyLiquidityRouter), type(uint256).max);
        t3mpl3Token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Add liquidity
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 100e18,
            salt: 0
        });

        modifyLiquidityRouter.modifyLiquidity(poolKey, params, ZERO_BYTES);

        // Approve tokens for swap router
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

    function testHookConfiguration() public {
        // Test hook basic configuration
        assertEq(hook.getHookDonationPercentage(), 10, "Initial donation percentage should be 10 (0.01%)");
        assertEq(hook.getDonationDenominator(), 100000, "Donation denominator should be 100000");
        assertEq(hook.qubitAddress(), 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720, "QUBIT address incorrect");
        assertEq(hook.getDonationManager(), address(this), "Donation manager should be deployer");
    }

    function testDonationPercentageUpdate() public {
        // Test initial percentage
        assertEq(hook.getHookDonationPercentage(), 10, "Initial donation percentage should be 10 (0.01%)");

        // Update to 1%
        uint256 newPercentage = 1000; // 1% = 1000/100000
        hook.setDonationPercentage(newPercentage);
        assertEq(hook.getHookDonationPercentage(), newPercentage, "Donation percentage not updated");
    }

    function testOnlyDonationManagerCanUpdatePercentage() public {
        vm.prank(alice);
        vm.expectRevert("Only donation manager");
        hook.setDonationPercentage(500);
    }

    function testDonationPercentageCap() public {
        vm.expectRevert("Donation too high");
        hook.setDonationPercentage(3001); // Over 3% cap
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

    function testBasicSwap() public {
        uint256 swapAmount = 1 ether;
        
        // Record initial balances
        uint256 qubitInitialBalance = weth.balanceOf(qubitAddress);
        uint256 aliceInitialWeth = weth.balanceOf(alice);

        // Perform swap as Alice
        vm.prank(alice);
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        BalanceDelta swapDelta = swap(poolKey, zeroForOne, int256(swapAmount), abi.encode(alice));

        // Check that some donation was taken (exact amount depends on pool math)
        uint256 qubitFinalBalance = weth.balanceOf(qubitAddress);
        assertGt(qubitFinalBalance, qubitInitialBalance, "No donation was taken");

        // Check that Alice's balance decreased
        uint256 aliceFinalWeth = weth.balanceOf(alice);
        assertGt(aliceInitialWeth - aliceFinalWeth, 0, "Alice's balance should decrease");
    }
}
