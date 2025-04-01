// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CharityManager
 * @notice Manages a registry of approved charities for a donation system
 * @dev Allows an admin to add, remove, and update charity information
 */
contract CharityManager is Ownable {
    // Struct to store charity information
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
    
    // Events
    event CharityAdded(uint256 indexed charityId, string name, address walletAddress);
    event CharityNameUpdated(uint256 indexed charityId, string name);
    event CharityAddressUpdated(uint256 indexed charityId, address oldAddress, address newAddress);
    event CharityDescriptionUpdated(uint256 indexed charityId, string description);
    event CharityRemoved(uint256 indexed charityId);
    
    /**
     * @notice Constructor initializes the contract with the deployer as owner
     */
    constructor() Ownable(msg.sender) {}
    
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
}