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
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

// Import our contracts
import {T3MPL3Token} from "../src/T3MPL3Token.sol";
import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";

contract SimpleDeploymentScript is Script {
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
        console.log("=== SIMPLE T3MPL3 DEPLOYMENT ===");
        
        vm.startBroadcast();
        
        // Deploy core infrastructure
        manager = IPoolManager(address(new PoolManager(address(0))));
        console.log("PoolManager deployed at:", address(manager));

        // Deploy routers
        lpRouter = new PoolModifyLiquidityTest(manager);
        swapRouter = new PoolSwapTest(manager);
        console.log("LiquidityRouter deployed at:", address(lpRouter));
        console.log("SwapRouter deployed at:", address(swapRouter));

        // Deploy T3MPL3 Token
        t3mpl3Token = new T3MPL3Token();
        console.log("T3MPL3Token deployed at:", address(t3mpl3Token));

        // Deploy mock WETH
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        console.log("Mock WETH deployed at:", address(weth));

        // Deploy SimpleTempleHook normally first
        hook = new SimpleTempleHook(manager);
        console.log("SimpleTempleHook deployed at:", address(hook));
        console.log("QUBIT charity address:", hook.qubitAddress());

        // Create pool key (order currencies properly)
        Currency currency0;
        Currency currency1;
        if (address(weth) < address(t3mpl3Token)) {
            currency0 = Currency.wrap(address(weth));
            currency1 = Currency.wrap(address(t3mpl3Token));
        } else {
            currency0 = Currency.wrap(address(t3mpl3Token));
            currency1 = Currency.wrap(address(weth));
        }

        // Create pool without hook first (for testing)
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)) // No hook for initial testing
        });

        // Initialize pool
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) * 2^96
        manager.initialize(poolKey, sqrtPriceX96);
        poolId = poolKey.toId();
        console.log("Pool initialized at 1:1 price (without hook for testing)");

        // Mint tokens for liquidity
        weth.mint(msg.sender, 100 ether);
        
        // Add initial liquidity
        weth.approve(address(lpRouter), type(uint256).max);
        t3mpl3Token.approve(address(lpRouter), type(uint256).max);

        int24 tickLower = -600;
        int24 tickUpper = 600;
        
        IPoolManager.ModifyLiquidityParams memory liqParams = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 1 ether,
            salt: 0
        });

        lpRouter.modifyLiquidity(poolKey, liqParams, "");
        console.log("Added initial liquidity to pool");

        vm.stopBroadcast();

        // Print summary
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("PoolManager:      ", address(manager));
        console.log("T3MPL3Token:      ", address(t3mpl3Token));
        console.log("SimpleTempleHook: ", address(hook));
        console.log("Mock WETH:        ", address(weth));
        console.log("SwapRouter:       ", address(swapRouter));
        console.log("LiquidityRouter:  ", address(lpRouter));
        console.log("QUBIT Address:    ", hook.qubitAddress());
        console.log("Pool ID:          ", vm.toString(PoolId.unwrap(poolId)));
        
        console.log("\nReady for testing!");
    }
}