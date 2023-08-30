pragma solidity >=8.0.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Mid is ERC20 {
    immutable address clExecutorAddress;
    constructor(address _clExecutorAddress) ERC20("Mid", "MID") {
        clExecutorAddress = _clExecutorAddress;
    }

    modifier onlyExecutor(){
        require(msg.sender == clExecutorAddress, "Not executor");
        _;
    }

    function burn(address account, uint256 amount) onlyExecutor() public{
        _burn(_msgSender(), amount);
    }

    function mint(address account, uint256 amount) onlyExecutor() public{
        _mint(_msgSender(), amount);
    }
}
