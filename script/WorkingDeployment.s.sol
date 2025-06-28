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

// Import our contracts
import {T3MPL3Token} from "../src/T3MPL3Token.sol";
import {SimpleTempleHook} from "../src/SimpleTempleHook.sol";

// This deployment mirrors exactly what works in T3MPL3SimpleTest.t.sol
contract WorkingDeploymentScript is Script {
    using PoolIdLibrary for PoolKey;

    function run() public {
        console.log("=== WORKING TEMPLE HOOK DEPLOYMENT ===");
        console.log("This uses the exact same pattern as our working tests");
        
        vm.startBroadcast();
        
        // Deploy manager
        IPoolManager manager = IPoolManager(address(new PoolManager(address(0))));
        console.log("PoolManager deployed at:", address(manager));

        // Deploy routers
        PoolModifyLiquidityTest modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        console.log("ModifyLiquidityRouter deployed at:", address(modifyLiquidityRouter));
        console.log("SwapRouter deployed at:", address(swapRouter));

        // Deploy tokens
        T3MPL3Token t3mpl3Token = new T3MPL3Token();
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        console.log("T3MPL3Token deployed at:", address(t3mpl3Token));
        console.log("WETH deployed at:", address(weth));

        // Deploy hook with correct flags (using deployCodeTo pattern from tests)
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG) ^ (0x4444 << 144)
        );
        
        console.log("Deploying hook to address:", flags);
        
        // This mimics the deployCodeTo functionality from tests
        bytes memory creationCode = abi.encodePacked(
            type(SimpleTempleHook).creationCode,
            abi.encode(address(manager))
        );
        
        address hookAddress;
        assembly {
            hookAddress := create2(0, add(creationCode, 0x20), mload(creationCode), 0)
        }
        
        if (hookAddress == address(0)) {
            revert("Hook deployment failed");
        }
        
        SimpleTempleHook hook = SimpleTempleHook(hookAddress);
        console.log("SimpleTempleHook deployed at:", address(hook));
        console.log("QUBIT charity address:", hook.qubitAddress());

        // Set up pool (same as test)
        Currency currency0;
        Currency currency1;
        if (address(weth) < address(t3mpl3Token)) {
            currency0 = Currency.wrap(address(weth));
            currency1 = Currency.wrap(address(t3mpl3Token));
        } else {
            currency0 = Currency.wrap(address(t3mpl3Token));
            currency1 = Currency.wrap(address(weth));
        }

        PoolKey memory poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        manager.initialize(poolKey, 79228162514264337593543950336);
        console.log("Pool initialized");

        // Add initial liquidity
        weth.mint(msg.sender, 1000 ether);
        weth.approve(address(modifyLiquidityRouter), type(uint256).max);
        t3mpl3Token.approve(address(modifyLiquidityRouter), type(uint256).max);

        int24 tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: 100e18,
            salt: 0
        });

        modifyLiquidityRouter.modifyLiquidity(poolKey, params, "");
        console.log("Added initial liquidity");

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("All contracts deployed and pool set up!");
        console.log("Hook donation mechanism ready for testing");
        
        console.log("\nCONTRACT ADDRESSES:");
        console.log("PoolManager:           ", address(manager));
        console.log("ModifyLiquidityRouter: ", address(modifyLiquidityRouter));
        console.log("SwapRouter:            ", address(swapRouter));
        console.log("T3MPL3Token:           ", address(t3mpl3Token));
        console.log("WETH:                  ", address(weth));
        console.log("SimpleTempleHook:      ", address(hook));
        console.log("QUBIT Address:         ", hook.qubitAddress());
    }
}