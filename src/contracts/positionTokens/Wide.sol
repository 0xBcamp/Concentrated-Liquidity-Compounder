//SPDX-License-Identifier: MIT

pragma solidity >=0.7.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Wide is ERC20 {
    address immutable clExecutorAddress;

    constructor(address _clExecutorAddress) ERC20("Wide", "WIDE") {
        clExecutorAddress = _clExecutorAddress;
    }

    modifier onlyExecutor() {
        require(msg.sender == clExecutorAddress, "Not executor");
        _;
    }

    function burn(uint256 amount) public onlyExecutor {
        _burn(_msgSender(), amount);
    }

    function mint(uint256 amount) public onlyExecutor {
        _mint(_msgSender(), amount);
    }
}
