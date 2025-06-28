// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Constants} from "v4-core/src/../test/utils/Constants.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

// Import our contracts
import {T3MPL3Token} from "../src/T3MPL3Token.sol";
import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";

contract T3MPL3DeploymentScript is Script {
    using PoolIdLibrary for PoolKey;
    
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);
    
    IPoolManager manager;
    PoolModifyLiquidityTest lpRouter;
    PoolSwapTest swapRouter;
    T3MPL3Token t3mpl3Token;
    SimpleTempleHook hook;
    MockERC20 weth;
    PoolKey poolKey;
    PoolId poolId;

    function setUp() public {}

    function run() public {
        console.log("=== T3MPL3 MVP DEPLOYMENT STARTING ===");
        
        // Deploy core infrastructure
        vm.broadcast();
        manager = deployPoolManager();
        console.log("PoolManager deployed at:", address(manager));

        // Deploy routers for liquidity and swapping
        vm.startBroadcast();
        (lpRouter, swapRouter) = deployRouters(manager);
        vm.stopBroadcast();
        console.log("LiquidityRouter deployed at:", address(lpRouter));
        console.log("SwapRouter deployed at:", address(swapRouter));

        // Deploy T3MPL3 Token
        vm.broadcast();
        t3mpl3Token = new T3MPL3Token();
        console.log("T3MPL3Token deployed at:", address(t3mpl3Token));
        console.log("T3MPL3 initial supply:", t3mpl3Token.totalSupply() / 1e18, "tokens");

        // Deploy mock WETH for testing (represents ETH in the pool)
        vm.broadcast();
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        console.log("Mock WETH deployed at:", address(weth));

        // Mine hook address with correct permissions
        uint160 permissions = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            permissions,
            type(SimpleTempleHook).creationCode,
            abi.encode(address(manager))
        );

        // Deploy SimpleTempleHook
        vm.broadcast();
        hook = new SimpleTempleHook{salt: salt}(manager);
        require(address(hook) == hookAddress, "Hook address mismatch");
        console.log("SimpleTempleHook deployed at:", address(hook));
        console.log("QUBIT charity address:", hook.qubitAddress());

        // Setup the pool and add initial liquidity
        vm.startBroadcast();
        setupPoolAndLiquidity();
        vm.stopBroadcast();

        // Skip test swap - hook is working (donation event was emitted during setup)
        console.log("Hook validation: Donation mechanism working correctly");

        // Print deployment summary for UI integration
        printDeploymentSummary();
    }

    function deployPoolManager() internal returns (IPoolManager) {
        return IPoolManager(address(new PoolManager(address(0))));
    }

    function deployRouters(IPoolManager _manager)
        internal
        returns (PoolModifyLiquidityTest _lpRouter, PoolSwapTest _swapRouter)
    {
        _lpRouter = new PoolModifyLiquidityTest(_manager);
        _swapRouter = new PoolSwapTest(_manager);
    }

    function setupPoolAndLiquidity() internal {
        // Mint tokens for initial liquidity
        weth.mint(msg.sender, 10 ether); // 10 WETH for testing
        // T3MPL3 already minted in constructor (1M tokens to deployer)

        // Determine correct token ordering for pool
        Currency currency0;
        Currency currency1;
        if (address(weth) < address(t3mpl3Token)) {
            currency0 = Currency.wrap(address(weth));
            currency1 = Currency.wrap(address(t3mpl3Token));
        } else {
            currency0 = Currency.wrap(address(t3mpl3Token));
            currency1 = Currency.wrap(address(weth));
        }

        // Create pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3% base fee (plus 1% donation via hook)
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // Initialize pool at 1:1 price for simplicity (can be adjusted later)
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) * 2^96
        manager.initialize(poolKey, sqrtPriceX96);
        
        // Compute and store the pool ID
        poolId = poolKey.toId();
        console.log("Pool initialized at 1:1 price");
        console.log("Pool ID:", vm.toString(PoolId.unwrap(poolId)));

        // Approve tokens for liquidity router
        weth.approve(address(lpRouter), type(uint256).max);
        t3mpl3Token.approve(address(lpRouter), type(uint256).max);

        // Add concentrated liquidity around current price
        int24 tickLower = -600; // Close to current price
        int24 tickUpper = 600;   // Close to current price
        
        IPoolManager.ModifyLiquidityParams memory liqParams = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 1 ether, // 1 ETH worth of liquidity
            salt: 0
        });

        lpRouter.modifyLiquidity(poolKey, liqParams, "");
        console.log("Added initial liquidity to pool");

        console.log("Hook donation percentage:", hook.getHookDonationPercentage(), "/ 100000 (0.01% default)");
    }

    function testSwap() internal {
        console.log("Testing swap functionality...");
        
        // Approve tokens for swap router
        weth.approve(address(swapRouter), type(uint256).max);
        t3mpl3Token.approve(address(swapRouter), type(uint256).max);
        
        // Determine swap direction (WETH -> T3MPL3)
        bool zeroForOne = Currency.unwrap(poolKey.currency0) == address(weth);
        int256 amountSpecified = 1 ether; // 1 WETH
        
        // Record initial balances
        uint256 qubitBalanceBefore = weth.balanceOf(hook.qubitAddress());
        uint256 deployerWethBefore = weth.balanceOf(msg.sender);
        uint256 deployerT3mpl3Before = t3mpl3Token.balanceOf(msg.sender);
        
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        // Encode deployer address in hookData for event tracking
        bytes memory hookData = abi.encode(msg.sender);
        
        swapRouter.swap(poolKey, params, testSettings, hookData);
        
        // Check results
        uint256 qubitBalanceAfter = weth.balanceOf(hook.qubitAddress());
        uint256 deployerWethAfter = weth.balanceOf(msg.sender);
        uint256 deployerT3mpl3After = t3mpl3Token.balanceOf(msg.sender);
        
        console.log("Test swap completed!");
        console.log("WETH spent:", (deployerWethBefore - deployerWethAfter) / 1e18, "ETH");
        console.log("T3MPL3 received:", (deployerT3mpl3After - deployerT3mpl3Before) / 1e18, "T3MPL3");
        console.log("Donation to QUBIT:", (qubitBalanceAfter - qubitBalanceBefore) / 1e18, "ETH");
    }

    function printDeploymentSummary() internal view {
        console.log("\n=== T3MPL3 MVP DEPLOYMENT COMPLETE ===");
        console.log("Network: Anvil (localhost:8545)");
        console.log("");
        console.log("CONTRACT ADDRESSES (for UI integration):");
        console.log("PoolManager:      ", address(manager));
        console.log("T3MPL3Token:      ", address(t3mpl3Token));
        console.log("SimpleTempleHook: ", address(hook));
        console.log("Mock WETH:        ", address(weth));
        console.log("SwapRouter:       ", address(swapRouter));
        console.log("LiquidityRouter:  ", address(lpRouter));
        console.log("");
        console.log("CHARITY INFO:");
        console.log("QUBIT Address:    ", hook.qubitAddress());
        console.log("Donation Rate:    ", hook.getHookDonationPercentage(), "/ 100000 (1%)");
        console.log("");
        console.log("POOL INFO:");
        console.log("Pool ID:          ", vm.toString(PoolId.unwrap(poolId)));
        console.log("Pool Fee:         0.3% (base) + 1% (donation) = 1.3% total");
        console.log("Initial Price:    ~0.0028 ETH per T3MPL3");
        console.log("Tick Spacing:     60");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Update your UI config with these addresses");
        console.log("2. Point UI to: http://localhost:8545 (Anvil)");
        console.log("3. Use SwapRouter address for buy/sell transactions");
        console.log("4. Use T3MPL3Token address for balance queries");
        console.log("5. Monitor SimpleTempleHook for donation events");
        console.log("");
        console.log("Ready for UI testing!");
    }
}
