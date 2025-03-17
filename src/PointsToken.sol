pragma solidity ^0.8.24;


contract PointsToken is ERC20, Owned {
    constructor() ERC20("Points Token", "POINTS", 18) Owned(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}