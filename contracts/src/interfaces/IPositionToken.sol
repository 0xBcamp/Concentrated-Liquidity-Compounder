pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IPositionToken is IERC20 {
    error notExecutorAddress(address observed, address expected);
    error notOwner(address observed, address expected);

    function setExecutor(address _clExecutorAddress) external;

    function burn(uint256 amount) external;

    function mint(uint256 amount) external;

    function rangePercentage() external view returns (uint8);

    function getTimestampOfFirstMint() external view returns (uint256);

    function getRelativeSupply() external view returns (uint256);
}
