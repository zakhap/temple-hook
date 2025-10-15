// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Shared constants used in scripts
contract Constants {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    /// @dev Official Uniswap v4 addresses on Base mainnet (Chain ID: 8453)
    IPoolManager constant POOLMANAGER = IPoolManager(address(0x498581fF718922c3f8e6A244956aF099B2652b2b));
    PositionManager constant posm = PositionManager(payable(address(0x7C5f5A4bBd8fD63184577525326123B519429bDc)));
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    /// @dev Additional Base mainnet v4 contracts (for reference)
    // Universal Router: 0x6ff5693b99212da76ad316178a184ab56d299b43
    // Quoter: 0x0d5e0f971ed27fbff6c2837bf31316121532048d
    // StateView: 0xa3c0c9b65bad0b08107aa264b0f3db444b867a71
}
