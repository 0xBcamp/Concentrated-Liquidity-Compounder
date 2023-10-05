//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IPositionToken.sol";

contract Wide is ERC20, IPositionToken {
    address immutable owner;
    address clExecutorAddress;
    uint8 rangePercentageTolerance = 10;

    uint256 firstMintTimestamp;

    constructor() ERC20("Wide", "WIDE") {
        owner = msg.sender;
    }

    modifier onlyExecutor() {
        if (
            msg.sender != clExecutorAddress || address(0) == clExecutorAddress
        ) {
            revert notExecutorAddress(msg.sender, clExecutorAddress);
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert notOwner(msg.sender, owner);
        }
        _;
    }

    function setExecutor(address _clExecutorAddress) public onlyOwner {
        clExecutorAddress = _clExecutorAddress;
    }

    function burn(uint256 amount) public onlyExecutor {
        _burn(_msgSender(), amount);
        if (totalSupply() == 0) {
            firstMintTimestamp = 0;
        }
    }

    function mint(uint256 amount) public onlyExecutor {
        if (totalSupply() == 0) {
            firstMintTimestamp = block.timestamp;
            _mint(_msgSender(), amount);
        } else {
            _mint(_msgSender(), amount * (getRelativeSupply() / totalSupply()));
        }
    }

    function rangePercentage() external view returns (uint8) {
        return rangePercentageTolerance;
    }

    function getTimestampOfFirstMint() external view returns (uint256) {
        return firstMintTimestamp;
    }

    function getRelativeSupply() public view returns (uint256) {
        if (firstMintTimestamp != 0) {
            return (firstMintTimestamp / block.timestamp) * totalSupply(); // Here can be some other function
        } else {
            return 0;
        }
    }
}
