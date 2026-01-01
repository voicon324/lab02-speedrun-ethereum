// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Lending.sol";
import "./Corn.sol";
import "./CornDEX.sol";

/**
 * @title FlashLoanLiquidator
 * @notice A contract that uses flash loans to liquidate positions without needing to hold CORN tokens
 * @dev Implements IFlashLoanRecipient to receive flash loans from the Lending contract
 */
contract FlashLoanLiquidator is IFlashLoanRecipient {
    Lending private immutable i_lending;
    CornDEX private immutable i_cornDEX;
    Corn private immutable i_corn;

    constructor(address _lending, address _cornDEX, address _corn) {
        i_lending = Lending(_lending);
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
    }

    /**
     * @notice Executes the flash loan operation - liquidates a position and repays the loan
     * @param amount The amount of CORN that was flash loaned
     * @param initiator The address that initiated the flash loan
     * @param extraParam The address of the borrower to liquidate
     * @return bool True if the operation was successful
     */
    function executeOperation(
        uint256 amount,
        address initiator,
        address extraParam
    ) external override returns (bool) {
        // Approve the Lending contract to use our CORN for liquidation
        i_corn.approve(address(i_lending), amount);

        // Liquidate the position - this will give us ETH in return
        i_lending.liquidate(extraParam);

        // Calculate how much ETH we need to get the required CORN amount
        uint256 ethNeeded = i_cornDEX.calculateXInput(
            amount,
            address(i_cornDEX).balance,
            i_corn.balanceOf(address(i_cornDEX))
        );

        // Swap ETH for CORN to repay the flash loan
        i_cornDEX.swap{value: ethNeeded}(ethNeeded);

        // Approve the Lending contract to retrieve the CORN for repayment
        i_corn.approve(address(i_lending), amount);

        // Send any remaining ETH back to the initiator (profit for the liquidator)
        uint256 remainingEth = address(this).balance;
        if (remainingEth > 0) {
            (bool success, ) = payable(initiator).call{value: remainingEth}("");
            require(success, "Failed to send remaining ETH to initiator");
        }

        return true;
    }

    /**
     * @notice Allows the contract to receive ETH from liquidation
     */
    receive() external payable {}
}
