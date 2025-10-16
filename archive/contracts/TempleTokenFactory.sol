// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TempleToken} from "./TempleToken.sol";

/**
 * @title TempleTokenFactory
 * @notice Factory contract for creating new charity-themed ERC20 tokens based on TempleToken standard
 * @dev Allows creation of new token contracts with custom parameters and tracks all deployed tokens
 */
contract TempleTokenFactory {
    address public owner;
    
    // Array to keep track of all tokens created through this factory
    address[] public deployedTokens;
    
    // Mapping from token address to creator address
    mapping(address => address) public tokenCreators;
    
    // Events
    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint256 initialSupply
    );
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @notice Creates a new TempleToken with specified parameters
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param initialSupply The initial supply of tokens (will be minted to the creator)
     * @return tokenAddress The address of the newly created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) external returns (address tokenAddress) {
        // Create a new TempleToken
        TempleToken newToken = new TempleToken(
            name,
            symbol,
            initialSupply
        );
        
        // Store the token address
        tokenAddress = address(newToken);
        deployedTokens.push(tokenAddress);
        
        // Record creator information
        tokenCreators[tokenAddress] = msg.sender;
        
        // Emit event
        emit TokenCreated(
            tokenAddress,
            msg.sender,
            name,
            symbol,
            initialSupply
        );
        
        return tokenAddress;
    }
    
    /**
     * @notice Returns the number of tokens deployed through this factory
     * @return The total count of deployed tokens
     */
    function getDeployedTokensCount() external view returns (uint256) {
        return deployedTokens.length;
    }
    
    /**
     * @notice Returns a list of all tokens deployed through this factory
     * @return An array of token addresses
     */
    function getAllDeployedTokens() external view returns (address[] memory) {
        return deployedTokens;
    }
    
    /**
     * @notice Returns tokens created by a specific address
     * @param creator The address of the token creator
     * @return An array of token addresses created by the specified creator
     */
    function getTokensByCreator(address creator) external view returns (address[] memory) {
        // First count tokens by this creator
        uint256 count = 0;
        for (uint256 i = 0; i < deployedTokens.length; i++) {
            if (tokenCreators[deployedTokens[i]] == creator) {
                count++;
            }
        }
        
        // Create and populate the result array
        address[] memory result = new address[](count);
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < deployedTokens.length; i++) {
            if (tokenCreators[deployedTokens[i]] == creator) {
                result[resultIndex] = deployedTokens[i];
                resultIndex++;
            }
        }
        
        return result;
    }
}