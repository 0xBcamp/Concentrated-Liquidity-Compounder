//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

contract Vault is ERC4626 {
    mapping(address => uint256) public shareHolder;

    constructor(
        ERC20 _asset
    ) ERC4626(_asset) ERC20(_asset.name(), _asset.symbol()) {}

    /**
     * @notice function to deposit assets and receive vault tokens in exchange
     * @param _assets amount of the asset token
     */
    function _deposit(uint _assets) public {
        require(_assets > 0, "Deposit less than Zero");
        deposit(_assets, msg.sender);
        shareHolder[msg.sender] += _assets;
    }

    /**
     * @notice Function to allow msg.sender to withdraw their deposit plus accrued interest
     * @param _shares amount of shares the user wants to convert
     * @param _receiver address of the user who will receive the assets
     */
    function _withdraw(uint _shares, address _receiver) public {
        require(_shares > 0, "Withdraw must be greater than Zero");
        require(_receiver != address(0), "Invalid receiver's Address");
        require(shareHolder[msg.sender] > 0, "Not a share holder");
        require(shareHolder[msg.sender] >= _shares, "Not enough shares");

        redeem(_shares, _receiver, msg.sender);
        shareHolder[msg.sender] -= _shares;
    }
}
