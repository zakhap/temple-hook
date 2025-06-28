// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract T3MPL3Token is ERC20 {
    constructor() ERC20("Temple Token", "T3MPL3") {
        // Mint 1 million tokens to deployer for initial liquidity
        _mint(msg.sender, 1_000_000 * 10**18);
    }
}
