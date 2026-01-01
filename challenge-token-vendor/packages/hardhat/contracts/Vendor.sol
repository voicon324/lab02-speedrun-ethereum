pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "./YourToken.sol";

contract Vendor is Ownable {
    event BuyTokens(address buyer, uint256 amountOfETH, uint256 amountOfTokens);
    event SellTokens(address seller, uint256 amountOfTokens, uint256 amountOfETH);

    YourToken public yourToken;

    constructor(address tokenAddress) Ownable(msg.sender) {
        yourToken = YourToken(tokenAddress);
    }

    uint256 public constant tokensPerEth = 100;

    // ToDo: create a payable buyTokens() function:
    function buyTokens() public payable {
        uint256 amountOfTokens = msg.value * tokensPerEth;
        require(yourToken.balanceOf(address(this)) >= amountOfTokens, "Not enough tokens in the contract");
        (bool sent) = yourToken.transfer(msg.sender, amountOfTokens);
        require(sent, "Failed to transfer tokens");

        emit BuyTokens(msg.sender, msg.value, amountOfTokens);
    }

    // ToDo: create a withdraw() function that lets the owner withdraw ETH
    function withdraw() public onlyOwner {
        uint256 ownerBalance = address(this).balance;
        require(ownerBalance > 0, "No ETH to withdraw");
        (bool sent, ) = msg.sender.call{ value: ownerBalance }("");
        require(sent, "Failed to send user ETH");
    }

    // ToDo: create a sellTokens(uint256 _amount) function:
    function sellTokens(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        uint256 amountOfETH = amount / tokensPerEth;
        require(address(this).balance >= amountOfETH, "Vendor has insufficient ETH");

        (bool sent) = yourToken.transferFrom(msg.sender, address(this), amount);
        require(sent, "Failed to transfer tokens from user");

        (bool ethSent, ) = msg.sender.call{ value: amountOfETH }("");
        require(ethSent, "Failed to send ETH to user");

        emit SellTokens(msg.sender, amount, amountOfETH);
    }
}
