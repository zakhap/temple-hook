// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @title Configurable ERC20 Token
/// @notice Simple ERC20 token with configurable name and symbol
contract ConfigurableToken is ERC20 {
    constructor(string memory name, string memory symbol, address recipient) ERC20(name, symbol, 18) {
        // Mint 10 billion tokens to specified recipient
        _mint(recipient, 10_000_000_000 * 10**18);
    }
}

/// @notice Deploys TWO tokens with CREATE2 ensuring Temple < USDC address order
contract DeployOrderedTokensScript is Script {
    function run() external {
        console.log("=== DEPLOYING ORDERED TOKENS WITH CREATE2 ===");
        console.log("Deployer:", msg.sender);

        // We need to find salts such that:
        // address(Temple) < address(USDC)

        bytes memory templeCreationCode = abi.encodePacked(
            type(ConfigurableToken).creationCode,
            abi.encode("Mock Temple7", "mTEMPLE7", msg.sender)
        );

        bytes memory usdcCreationCode = abi.encodePacked(
            type(ConfigurableToken).creationCode,
            abi.encode("Mock USDC7", "mUSDC7", msg.sender)
        );

        console.log("\n=== MINING SALTS ===");
        console.log("Finding salts to ensure Temple < USDC...");

        bytes32 templeSalt;
        bytes32 usdcSalt;
        address templeAddress;
        address usdcAddress;

        // Try different salts until we find Temple < USDC
        // Forge uses the CREATE2 deployer proxy: 0x4e59b44847b379578588920cA78FbF26c0B4956C
        address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

        for (uint256 i = 12000; i < 13000; i++) {
            templeSalt = bytes32(i);
            usdcSalt = bytes32(i + 1000);

            templeAddress = computeCreate2Address(
                templeSalt,
                keccak256(templeCreationCode),
                create2Deployer
            );

            usdcAddress = computeCreate2Address(
                usdcSalt,
                keccak256(usdcCreationCode),
                create2Deployer
            );

            if (templeAddress < usdcAddress) {
                console.log("Found valid salts!");
                console.log("Temple salt:", uint256(templeSalt));
                console.log("USDC salt:", uint256(usdcSalt));
                console.log("Temple address:", templeAddress);
                console.log("USDC address:", usdcAddress);
                break;
            }
        }

        require(templeAddress < usdcAddress, "Could not find valid salt combination");

        vm.startBroadcast();

        // Deploy Temple token (tokens minted to msg.sender)
        ConfigurableToken templeToken = new ConfigurableToken{salt: templeSalt}("Mock Temple7", "mTEMPLE7", msg.sender);
        require(address(templeToken) == templeAddress, "Temple address mismatch");

        // Deploy USDC token (tokens minted to msg.sender)
        ConfigurableToken usdcToken = new ConfigurableToken{salt: usdcSalt}("Mock USDC7", "mUSDC7", msg.sender);
        require(address(usdcToken) == usdcAddress, "USDC address mismatch");

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("Temple Token:", address(templeToken));
        console.log("USDC Token:", address(usdcToken));
        console.log("Order verified: Temple < USDC =", address(templeToken) < address(usdcToken));

        console.log("\n=== EXPORT ADDRESSES ===");
        console.log("export MOCK_TEMPLE_ADDRESS=", address(templeToken));
        console.log("export MOCK_USDC_ADDRESS=", address(usdcToken));
    }

    function computeCreate2Address(
        bytes32 salt,
        bytes32 initCodeHash,
        address deployer
    ) internal pure override returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            initCodeHash
        )))));
    }
}
