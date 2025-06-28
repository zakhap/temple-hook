// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Fixtures} from "./utils/Fixtures.sol";

import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";
import {T3MPL3Token} from "../src/T3MPL3Token.sol";

contract T3MPL3UnitTest is Test, Fixtures {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    SimpleTempleHook hook;
    T3MPL3Token t3mpl3Token;
    MockERC20 weth;
    PoolKey poolKey;

    address alice = address(0x1);
    address qubitAddress;

    function setUp() public {
        // Deploy manager and basic infrastructure
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

        // Create pool key but don't initialize the pool yet
        Currency currency0;
        Currency currency1;
        if (address(weth) < address(t3mpl3Token)) {
            currency0 = Currency.wrap(address(weth));
            currency1 = Currency.wrap(address(t3mpl3Token));
        } else {
            currency0 = Currency.wrap(address(t3mpl3Token));
            currency1 = Currency.wrap(address(weth));
        }

        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
    }

    function testTokenDeployment() public view {
        assertEq(t3mpl3Token.name(), "Temple Token");
        assertEq(t3mpl3Token.symbol(), "T3MPL3");
        assertEq(t3mpl3Token.totalSupply(), 1_000_000 * 10**18);
        assertEq(t3mpl3Token.balanceOf(address(this)), 1_000_000 * 10**18);
    }

    function testHookConfiguration() public view {
        assertEq(hook.getHookDonationPercentage(), 10, "Initial donation percentage should be 10 (0.01%)");
        assertEq(hook.getDonationDenominator(), 100000, "Donation denominator should be 100000");
        assertEq(hook.qubitAddress(), 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720, "QUBIT address incorrect");
        assertEq(hook.getDonationManager(), address(this), "Donation manager should be deployer");
    }

    function testHookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertFalse(permissions.beforeSwap, "beforeSwap should be disabled");
        assertTrue(permissions.afterSwap, "afterSwap should be enabled");
        assertTrue(permissions.afterSwapReturnDelta, "afterSwapReturnDelta should be enabled");
        assertFalse(permissions.beforeAddLiquidity, "beforeAddLiquidity should be disabled");
        assertFalse(permissions.afterAddLiquidity, "afterAddLiquidity should be disabled");
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
        hook.setDonationPercentage(1001); // Over 1% cap
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

    function testPoolKeyCreation() public view {
        assertTrue(address(poolKey.hooks) == address(hook), "Hook address should match");
        assertEq(poolKey.fee, 3000, "Pool fee should be 3000 (0.3%)");
        assertEq(poolKey.tickSpacing, 60, "Tick spacing should be 60");
    }
}
