pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

abstract contract PositionToken is ERC20 {
    error notExecutorAddress(address observed, address expected);
    error notOwner(address observed, address expected);

    address immutable owner;
    address clExecutorAddress;

    uint256 firstMintTimestamp;

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

    function mint(uint256 amount) public onlyExecutor returns (uint256) {
        uint256 retVal;
        if (totalSupply() == 0) {
            firstMintTimestamp = block.timestamp;
            _mint(_msgSender(), amount);
            retVal = amount;
        } else {
            _mint(_msgSender(), (amount * getRelativeSupply()) / totalSupply());
            retVal = (amount * getRelativeSupply()) / totalSupply();
        }
        return retVal;
    }

    function rangePercentage() external view virtual returns (uint8);

    function getTimestampOfFirstMint() external view returns (uint256) {
        return firstMintTimestamp;
    }

    function getRelativeSupply() public view returns (uint256) {
        if (firstMintTimestamp != 0) {
            return (firstMintTimestamp * totalSupply()) / block.timestamp; // Here can be some other function
        } else {
            return 0;
        }
    }

    // function _beforeTokenTransfer(
    //     address from,
    //     address to,
    //     uint256 amount
    // ) internal override {}
}
