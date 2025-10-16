// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {TempleToken} from "./TempleToken.sol";

/**
 * @title TempleCharitableHook
 * @notice An all-in-one Uniswap v4 hook that implements charity management, token creation, and donation collection
 * @dev This contract implements its own versions of SimpleTempLeHook, CharityManager, and TempleTokenFactory
 * functionalities to avoid inheritance conflicts.
 */
contract TempleCharitableHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    
    // ================ State Variables ================
    
    // Owner and access control
    address public owner;
    address private _donationManager;
    
    // Charitable donations configuration
    address public immutable DEFAULT_CHARITY_ADDRESS;
    uint256 private _hookDonationPercentage = 10; // 0.01% default donation
    uint256 private constant DONATION_DENOMINATOR = 100000;
    
    // Charity management
    struct Charity {
        string name;
        address payable walletAddress;
        string description;
    }
    
    // Mapping from charity ID to Charity struct
    mapping(uint256 => Charity) private _charities;
    
    // Mapping to check if an address is a registered charity
    mapping(address => uint256) private _addressToCharityId;
    
    // Array to store all charity IDs
    uint256[] private _charityIds;
    
    // Counter for charity IDs
    uint256 private _nextCharityId = 1;
    
    // Token factory
    address[] public deployedTokens;
    mapping(address => address) public tokenCreators;
    
    // Donation tracking
    mapping(uint256 => uint256) public charityDonations; // charityId => total donations
    mapping(address => uint256) public tokenToCharityId; // token address => charity ID
    
    // ================ Events ================
    
    // Charity management events
    event CharityAdded(uint256 indexed charityId, string name, address walletAddress);
    event CharityNameUpdated(uint256 indexed charityId, string name);
    event CharityAddressUpdated(uint256 indexed charityId, address oldAddress, address newAddress);
    event CharityDescriptionUpdated(uint256 indexed charityId, string description);
    event CharityRemoved(uint256 indexed charityId);
    
    // Token factory events
    event TokenCreated(address indexed tokenAddress, address indexed creator, string name, string symbol, uint256 initialSupply);
    
    // Donation events
    event CharitableDonationTaken(address indexed user, PoolId indexed poolId, Currency indexed donationCurrency, uint256 donationAmount);
    event DonationPercentageUpdated(uint256 newDonationPercentage);
    event DonationManagerUpdated(address newDonationManager);
    event DefaultCharityUpdated(address indexed newDefaultCharity);
    event CharityTokenCreated(uint256 indexed charityId, address tokenAddress, string name, string symbol);
    
    // ================ Constructor ================
    
    constructor(IPoolManager _poolManager, address initialDefaultCharity) BaseHook(_poolManager) {
        owner = msg.sender;
        _donationManager = msg.sender;
        DEFAULT_CHARITY_ADDRESS = initialDefaultCharity;
    }
    
    // ================ Modifiers ================
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyDonationManager() {
        require(msg.sender == _donationManager, "Only donation manager");
        _;
    }
    
    // ================ Hook Configuration ================
    
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    // ================ Ownership & Management ================
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }
    
    function setDonationManager(address newDonationManager) external onlyOwner {
        require(newDonationManager != address(0), "Zero address");
        _donationManager = newDonationManager;
        emit DonationManagerUpdated(newDonationManager);
    }
    
    function getDonationManager() external view returns (address) {
        return _donationManager;
    }
    
    // ================ Donation Configuration ================
    
    function setDonationPercentage(uint256 newDonationPercentage) external onlyDonationManager {
        require(newDonationPercentage <= 1000, "Donation too high"); // Max 1% (1000/100000)
        _hookDonationPercentage = newDonationPercentage;
        emit DonationPercentageUpdated(newDonationPercentage);
    }
    
    function getHookDonationPercentage() external view returns (uint256) {
        return _hookDonationPercentage;
    }
    
    function getDonationDenominator() external pure returns (uint256) {
        return DONATION_DENOMINATOR;
    }
    
    function getDefaultCharityAddress() external view returns (address) {
        return DEFAULT_CHARITY_ADDRESS;
    }
    
    // ================ Charity Management ================
    
    /**
     * @notice Adds a new charity to the registry
     * @param name The name of the charity
     * @param walletAddress The wallet address where donations will be sent
     * @param description A brief description of the charity
     * @return The ID of the newly added charity
     */
    function addCharity(
        string memory name,
        address payable walletAddress,
        string memory description
    ) external onlyOwner returns (uint256) {
        require(walletAddress != address(0), "Invalid wallet address");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(_addressToCharityId[walletAddress] == 0, "Address already registered");
        
        uint256 charityId = _nextCharityId;
        _nextCharityId++;
        
        _charities[charityId] = Charity({
            name: name,
            walletAddress: walletAddress,
            description: description
        });
        
        _addressToCharityId[walletAddress] = charityId;
        _charityIds.push(charityId);
        
        emit CharityAdded(charityId, name, walletAddress);
        
        return charityId;
    }
    
    /**
     * @notice Updates the name of an existing charity
     * @param charityId The ID of the charity to update
     * @param name The updated name of the charity
     */
    function updateCharityName(
        uint256 charityId,
        string memory name
    ) external onlyOwner {
        require(_charityExists(charityId), "Charity does not exist");
        require(bytes(name).length > 0, "Name cannot be empty");
        
        _charities[charityId].name = name;
        
        emit CharityNameUpdated(charityId, name);
    }
    
    /**
     * @notice Updates the wallet address of an existing charity
     * @param charityId The ID of the charity to update
     * @param walletAddress The updated wallet address
     */
    function updateCharityAddress(
        uint256 charityId,
        address payable walletAddress
    ) external onlyOwner {
        require(_charityExists(charityId), "Charity does not exist");
        require(walletAddress != address(0), "Invalid wallet address");
        require(_addressToCharityId[walletAddress] == 0 || _addressToCharityId[walletAddress] == charityId, 
                "Address already registered to another charity");
        
        // Get the old address to remove from mapping
        address oldAddress = _charities[charityId].walletAddress;
        
        // Update the address mappings
        delete _addressToCharityId[oldAddress];
        _addressToCharityId[walletAddress] = charityId;
        
        // Update the charity struct
        _charities[charityId].walletAddress = walletAddress;
        
        emit CharityAddressUpdated(charityId, oldAddress, walletAddress);
    }
    
    /**
     * @notice Updates the description of an existing charity
     * @param charityId The ID of the charity to update
     * @param description The updated description
     */
    function updateCharityDescription(
        uint256 charityId,
        string memory description
    ) external onlyOwner {
        require(_charityExists(charityId), "Charity does not exist");
        
        _charities[charityId].description = description;
        
        emit CharityDescriptionUpdated(charityId, description);
    }
    
    /**
     * @notice Permanently removes a charity from the registry
     * @param charityId The ID of the charity to remove
     */
    function removeCharity(uint256 charityId) external onlyOwner {
        require(_charityExists(charityId), "Charity does not exist");
        
        // Get the address to remove from mapping
        address charityAddress = _charities[charityId].walletAddress;
        
        // Remove from charity IDs array
        for (uint256 i = 0; i < _charityIds.length; i++) {
            if (_charityIds[i] == charityId) {
                // Replace with the last element and pop
                _charityIds[i] = _charityIds[_charityIds.length - 1];
                _charityIds.pop();
                break;
            }
        }
        
        // Remove address mapping
        delete _addressToCharityId[charityAddress];
        
        // Remove charity data
        delete _charities[charityId];
        
        emit CharityRemoved(charityId);
    }
    
    /**
     * @notice Gets information about a specific charity
     * @param charityId The ID of the charity
     * @return name The name of the charity
     * @return walletAddress The wallet address of the charity
     * @return description The description of the charity
     */
    function getCharity(uint256 charityId) external view returns (
        string memory name,
        address walletAddress,
        string memory description
    ) {
        require(_charityExists(charityId), "Charity does not exist");
        Charity memory charity = _charities[charityId];
        
        return (
            charity.name,
            charity.walletAddress,
            charity.description
        );
    }
    
    /**
     * @notice Gets charity ID from a wallet address
     * @param walletAddress The wallet address to check
     * @return The charity ID (0 if not found)
     */
    function getCharityIdByAddress(address walletAddress) external view returns (uint256) {
        return _addressToCharityId[walletAddress];
    }
    
    /**
     * @notice Gets a list of all charity IDs
     * @return An array of charity IDs
     */
    function getAllCharityIds() external view returns (uint256[] memory) {
        return _charityIds;
    }
    
    /**
     * @notice Gets a count of charities
     * @return The number of charities
     */
    function getCharityCount() external view returns (uint256) {
        return _charityIds.length;
    }
    
    /**
     * @notice Gets detailed information for all charities
     * @return ids Array of charity IDs
     * @return names Array of charity names
     * @return addresses Array of charity wallet addresses
     */
    function getAllCharities() external view returns (
        uint256[] memory ids,
        string[] memory names,
        address[] memory addresses
    ) {
        uint256 count = _charityIds.length;
        
        ids = new uint256[](count);
        names = new string[](count);
        addresses = new address[](count);
        
        for (uint256 i = 0; i < count; i++) {
            uint256 charityId = _charityIds[i];
            Charity memory charity = _charities[charityId];
            
            ids[i] = charityId;
            names[i] = charity.name;
            addresses[i] = charity.walletAddress;
        }
        
        return (ids, names, addresses);
    }
    
    /**
     * @notice Checks if an address belongs to a registered charity
     * @param walletAddress The address to check
     * @return Whether the address belongs to a registered charity
     */
    function isRegisteredCharityAddress(address walletAddress) external view returns (bool) {
        return _addressToCharityId[walletAddress] != 0;
    }
    
    /**
     * @notice Gets the wallet address for a specific charity
     * @param charityId The ID of the charity
     * @return The wallet address of the charity
     */
    function getCharityAddress(uint256 charityId) external view returns (address) {
        require(_charityExists(charityId), "Charity does not exist");
        return _charities[charityId].walletAddress;
    }
    
    /**
     * @notice Gets the name for a specific charity
     * @param charityId The ID of the charity
     * @return The name of the charity
     */
    function getCharityName(uint256 charityId) external view returns (string memory) {
        require(_charityExists(charityId), "Charity does not exist");
        return _charities[charityId].name;
    }
    
    /**
     * @notice Gets the description for a specific charity
     * @param charityId The ID of the charity
     * @return The description of the charity
     */
    function getCharityDescription(uint256 charityId) external view returns (string memory) {
        require(_charityExists(charityId), "Charity does not exist");
        return _charities[charityId].description;
    }
    
    /**
     * @notice Internal function to check if a charity exists
     * @param charityId The ID of the charity to check
     * @return Whether the charity exists
     */
    function _charityExists(uint256 charityId) internal view returns (bool) {
        return _charities[charityId].walletAddress != address(0);
    }
    
    // ================ Token Factory ================
    
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
    
    // ================ Integrated Functions ================
    
    /**
     * @notice Creates a charity and automatically creates a token for it
     * @param name The charity name
     * @param walletAddress The charity's wallet address
     * @param description The charity's description
     * @param tokenName The token name
     * @param tokenSymbol The token symbol
     * @param initialSupply The initial token supply
     * @return charityId The ID of the newly created charity
     * @return tokenAddress The address of the newly created token
     */
    function createCharityWithToken(
        string memory name,
        address payable walletAddress,
        string memory description,
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialSupply
    ) external onlyOwner returns (uint256 charityId, address tokenAddress) {
        // Create charity
        charityId = this.addCharity(name, walletAddress, description);
        
        // Create token
        tokenAddress = this.createToken(tokenName, tokenSymbol, initialSupply);
        
        // Map token to charity
        tokenToCharityId[tokenAddress] = charityId;
        
        emit CharityTokenCreated(charityId, tokenAddress, tokenName, tokenSymbol);
        
        return (charityId, tokenAddress);
    }
    
    /**
     * @notice Associate an existing token with a charity
     * @param tokenAddress The token address
     * @param charityId The charity ID
     */
    function mapTokenToCharity(address tokenAddress, uint256 charityId) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(_charityExists(charityId), "Charity doesn't exist");
        
        tokenToCharityId[tokenAddress] = charityId;
    }
    
    /**
     * @notice Remove the association between a token and a charity
     * @param tokenAddress The token address
     */
    function unmapTokenFromCharity(address tokenAddress) external onlyOwner {
        delete tokenToCharityId[tokenAddress];
    }
    
    /**
     * @notice Get total donations for a specific charity
     * @param charityId The ID of the charity
     * @return The total amount donated to this charity
     */
    function getCharityDonationTotal(uint256 charityId) external view returns (uint256) {
        return charityDonations[charityId];
    }
    
    /**
     * @notice Get the charity associated with a specific token
     * @param tokenAddress The address of the token
     * @return The ID of the associated charity (0 if none)
     */
    function getCharityForToken(address tokenAddress) external view returns (uint256) {
        return tokenToCharityId[tokenAddress];
    }
    
    /**
     * @notice Transfer ownership of a charity token to its associated charity
     * @param tokenAddress The token address
     */
    function transferTokenToCharity(address tokenAddress) external onlyOwner {
        uint256 charityId = tokenToCharityId[tokenAddress];
        require(charityId != 0, "Token not associated with charity");
        
        address charityAddress = _charities[charityId].walletAddress;
        require(charityAddress != address(0), "Charity does not exist");
        
        TempleToken token = TempleToken(tokenAddress);
        token.transferOwnership(charityAddress);
    }
    
    // ================ Hook Data Utilities ================
    
    /**
     * @notice Creates hookData for the swap function encoding user address
     * @param user The address of the user to encode
     * @return Encoded hook data
     */
    function getHookData(address user) public pure returns (bytes memory) {
        return abi.encode(user);
    }

    /**
     * @notice Parses user address from hookData
     * @param data The hookData to parse
     * @return user The user address
     */
    function parseHookData(
        bytes calldata data
    ) public pure returns (address user) {
        return abi.decode(data, (address));
    }
    
    // ================ Hook Implementation ================
    
    /**
     * @notice Uniswap v4 hook function called before swaps
     * @dev Takes a percentage of the swap amount as a donation to the appropriate charity
     */
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Extract info and calculate donation
        (address charityAddress, Currency donationCurrency, uint256 donationAmount, address user) = 
            _prepareDonation(sender, key, params, hookData);
        
        // Update tracking for charity donations if needed
        address tokenAddress = Currency.unwrap(donationCurrency);
        uint256 charityId = tokenToCharityId[tokenAddress];
        if (charityId != 0 && _charityExists(charityId)) {
            charityDonations[charityId] += donationAmount;
        }
        
        // Take the donation
        poolManager.take(donationCurrency, charityAddress, donationAmount);
        
        // Create BeforeSwapDelta
        BeforeSwapDelta returnDelta = toBeforeSwapDelta(
            int128(int256(donationAmount)), // Specified delta (donation amount)
            0                               // Unspecified delta (no change)
        );
        
        // Emit event
        PoolId poolId = key.toId();
        emit CharitableDonationTaken(user, poolId, donationCurrency, donationAmount);
        
        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }
    
    /**
     * @notice Helper function to prepare donation details
     * @dev Extracts the donation information to avoid stack too deep errors
     */
    function _prepareDonation(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) private view returns (
        address charityAddress,
        Currency donationCurrency,
        uint256 donationAmount,
        address user
    ) {
        // Extract the user address from hookData
        user = hookData.length > 0 ? parseHookData(hookData) : sender;
        
        // Calculate absolute swap amount (convert negative to positive)
        uint256 swapAmount = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
        
        // Calculate donation amount based on percentage
        donationAmount = (swapAmount * _hookDonationPercentage) / DONATION_DENOMINATOR;
        
        // Determine which currency the donation should be taken in
        donationCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        
        // Determine the charity address (using default charity if no specific one is found)
        charityAddress = DEFAULT_CHARITY_ADDRESS;
        
        // Check if this currency is associated with a specific charity
        address tokenAddress = Currency.unwrap(donationCurrency);
        uint256 charityId = tokenToCharityId[tokenAddress];
        
        if (charityId != 0) {
            // If token is associated with a charity, get that charity's wallet address
            if (_charityExists(charityId)) {
                charityAddress = _charities[charityId].walletAddress;
                
                // Update donation tracking - we'll do this in the main function to keep this one view-only
            }
        }
        
        return (charityAddress, donationCurrency, donationAmount, user);
    }
}