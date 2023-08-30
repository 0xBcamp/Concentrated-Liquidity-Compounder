pragma solidity >=8.0.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Narrow is ERC20 {
    immutable address clExecutorAddress;
    constructor(address _clExecutorAddress) ERC20("Narrow", "NARROW") {
        clExecutorAddress = _clExecutorAddress;
    }

    modifier onlyExecutor(){
        require(msg.sender == clExecutorAddress, "Not executor");
        _;
    }

    function burn(uint256 amount) onlyExecutor() public{
        _burn(_msgSender(), amount);
    }

    function mint(uint256 amount) onlyExecutor() public{
        _mint(_msgSender(), amount);
    }
}
