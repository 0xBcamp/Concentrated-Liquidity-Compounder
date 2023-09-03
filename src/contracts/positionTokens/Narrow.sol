//SPDX-License-Identifier: MIT

pragma solidity >=0.7.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Narrow is ERC20 {
    address immutable owner;
    address clExecutorAddress;

    constructor() ERC20("Narrow", "NARROW") {
        owner = msg.sender;
    }

    modifier onlyExecutor() {
        require(
            msg.sender == clExecutorAddress && address(0) == clExecutorAddress,
            "Not executor or executor not set"
        );
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function setExecutor(address _clExecutorAddress) public onlyOwner {
        clExecutorAddress = _clExecutorAddress;
    }

    function burn(uint256 amount) public onlyExecutor {
        _burn(_msgSender(), amount);
    }

    function mint(uint256 amount) public onlyExecutor {
        _mint(_msgSender(), amount);
    }
}
