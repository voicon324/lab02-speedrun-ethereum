// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Lending.sol";
import "./CornDEX.sol";
import "./Corn.sol";

contract Leverage {
    Lending private i_lending;
    CornDEX private i_cornDEX;
    Corn private i_corn;
    address public owner;

    constructor(address _lending, address _cornDEX, address _corn) {
        i_lending = Lending(_lending);
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
        // Approve lending contract to pull CORN for repayment
        i_corn.approve(_lending, type(uint256).max);
        // Approve DEX to pull CORN for swaps
        i_corn.approve(_cornDEX, type(uint256).max);
    }

    /**
     * @notice Allows a user to claim ownership of this contract before opening a position
     */
    function claimOwnership() external {
        require(owner == address(0), "Already has an owner");
        owner = msg.sender;
    }

    /**
     * @notice Opens a leveraged position by iteratively depositing, borrowing, and swapping
     * @param reserve The amount of ETH to keep as reserve after looping (safety margin)
     * @dev If reserve is 0, the position will be at maximum leverage (right at liquidation threshold)
     */
    function openLeveragedPosition(uint256 reserve) external payable {
        require(msg.sender == owner, "Not the owner");
        require(msg.value > 0, "Must send ETH");

        uint256 ethBalance = msg.value;

        while (ethBalance > reserve) {
            // Add all available ETH as collateral
            i_lending.addCollateral{value: ethBalance}();

            // Calculate max CORN we can borrow based on this collateral
            uint256 maxBorrow = i_lending.getMaxBorrowAmount(ethBalance);
            
            if (maxBorrow == 0) {
                break;
            }

            // Borrow max CORN
            i_lending.borrowCorn(maxBorrow);

            // Swap CORN for ETH on the DEX
            uint256 ethReceived = i_cornDEX.swap(maxBorrow);

            ethBalance = ethReceived;

            // If ETH received is less than or equal to reserve, break
            if (ethBalance <= reserve) {
                break;
            }
        }

        // If any ETH left, deposit it as final collateral
        if (ethBalance > 0) {
            i_lending.addCollateral{value: ethBalance}();
        }
    }

    /**
     * @notice Closes the leveraged position by iteratively withdrawing, swapping, and repaying
     */
    function closeLeveragedPosition() external {
        require(msg.sender == owner, "Not the owner");

        uint256 debt = i_lending.s_userBorrowed(address(this));

        while (debt > 0) {
            // Get max withdrawable collateral
            uint256 maxWithdraw = i_lending.getMaxWithdrawableCollateral(address(this));
            
            if (maxWithdraw == 0) {
                break;
            }

            // Withdraw collateral
            i_lending.withdrawCollateral(maxWithdraw);

            // Swap ETH for CORN
            uint256 cornReceived = i_cornDEX.swap{value: maxWithdraw}(maxWithdraw);

            // Repay as much debt as possible
            uint256 repayAmount = cornReceived > debt ? debt : cornReceived;
            i_lending.repayCorn(repayAmount);

            // Update debt
            debt = i_lending.s_userBorrowed(address(this));
        }
    }

    /**
     * @notice Allows owner to withdraw remaining ETH after position is closed
     */
    function withdraw() external {
        require(msg.sender == owner, "Not the owner");
        
        // Withdraw all remaining collateral
        uint256 collateral = i_lending.s_userCollateral(address(this));
        if (collateral > 0) {
            i_lending.withdrawCollateral(collateral);
        }

        // Transfer all ETH to owner
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner).call{value: balance}("");
            require(success, "Transfer failed");
        }

        // Transfer any remaining CORN to owner
        uint256 cornBalance = i_corn.balanceOf(address(this));
        if (cornBalance > 0) {
            i_corn.transfer(owner, cornBalance);
        }
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
