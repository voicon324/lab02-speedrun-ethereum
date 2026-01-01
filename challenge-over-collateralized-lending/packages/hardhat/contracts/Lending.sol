// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Corn.sol";
import "./CornDEX.sol";

error Lending__InvalidAmount();
error Lending__TransferFailed();
error Lending__UnsafePositionRatio();
error Lending__BorrowingFailed();
error Lending__RepayingFailed();
error Lending__PositionSafe();
error Lending__NotLiquidatable();
error Lending__InsufficientLiquidatorCorn();

contract Lending is Ownable {
    uint256 private constant COLLATERAL_RATIO = 120; // 120% collateralization required
    uint256 private constant LIQUIDATOR_REWARD = 10; // 10% reward for liquidators

    Corn private i_corn;
    CornDEX private i_cornDEX;

    mapping(address => uint256) public s_userCollateral; // User's collateral balance
    mapping(address => uint256) public s_userBorrowed; // User's borrowed corn balance

    event CollateralAdded(address indexed user, uint256 indexed amount, uint256 price);
    event CollateralWithdrawn(address indexed user, uint256 indexed amount, uint256 price);
    event AssetBorrowed(address indexed user, uint256 indexed amount, uint256 price);
    event AssetRepaid(address indexed user, uint256 indexed amount, uint256 price);
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 amountForLiquidator,
        uint256 liquidatedUserDebt,
        uint256 price
    );

    constructor(address _cornDEX, address _corn) Ownable(msg.sender) {
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
        i_corn.approve(address(this), type(uint256).max);
    }

    /**
     * @notice Allows users to add collateral to their account
     */
    function addCollateral() public payable {
        if (msg.value == 0) {
            revert Lending__InvalidAmount();
        }

        s_userCollateral[msg.sender] += msg.value;
        emit CollateralAdded(msg.sender, msg.value, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows users to withdraw collateral as long as it doesn't make them liquidatable
     * @param amount The amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) public {
        if (amount == 0) {
            revert Lending__InvalidAmount();
        }

        if (s_userCollateral[msg.sender] < amount) {
            revert Lending__InvalidAmount();
        }

        s_userCollateral[msg.sender] -= amount;

        // Validate AFTER withdrawal to ensure new position is safe
        _validatePosition(msg.sender);

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Lending__TransferFailed();
        }
        emit CollateralWithdrawn(msg.sender, amount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Calculates the total collateral value for a user based on their collateral balance
     * @param user The address of the user to calculate the collateral value for
     * @return uint256 The collateral value
     */
    function calculateCollateralValue(address user) public view returns (uint256) {
        return s_userCollateral[user] * i_cornDEX.currentPrice();
    }

    /**
     * @notice Calculates the position ratio for a user to ensure they are within safe limits
     * @param user The address of the user to calculate the position ratio for
     * @return uint256 The position ratio as a percentage (e.g., 120 for 120%)
     */
    function _calculatePositionRatio(address user) internal view returns (uint256) {
        // collateralValue has 36 decimals (18 from collateral + 18 from price)
        // borrowed has 18 decimals
        // We need to return a percentage comparable to COLLATERAL_RATIO (120)
        // Formula: (collateralValue * 100) / (borrowed * 1e18)
        return (calculateCollateralValue(user) * 100) / (s_userBorrowed[user] * 1e18);
    }

    /**
     * @notice Checks if a user's position can be liquidated
     * @param user The address of the user to check
     * @return bool True if the position is liquidatable, false otherwise
     */
    function isLiquidatable(address user) public view returns (bool) {
        // If user has no debt, they can't be liquidated
        if (s_userBorrowed[user] == 0) {
            return false;
        }
        return _calculatePositionRatio(user) < COLLATERAL_RATIO;
    }

    /**
     * @notice Internal view method that reverts if a user's position is unsafe
     * @param user The address of the user to validate
     */
    function _validatePosition(address user) internal view {
        if (isLiquidatable(user)) {
            revert Lending__UnsafePositionRatio();
        }
    }

    /**
     * @notice Allows users to borrow corn based on their collateral
     * @param borrowAmount The amount of corn to borrow
     */
    function borrowCorn(uint256 borrowAmount) public {
        if (borrowAmount == 0) {
            revert Lending__InvalidAmount();
        }
        s_userBorrowed[msg.sender] += borrowAmount;

        // Validate AFTER adding to borrowed to ensure new position is safe
        _validatePosition(msg.sender);

        bool success = i_corn.transfer(msg.sender, borrowAmount);
        if (!success) {
            revert Lending__BorrowingFailed();
        }

        emit AssetBorrowed(msg.sender, borrowAmount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows users to repay corn and reduce their debt
     * @param repayAmount The amount of corn to repay
     */
    function repayCorn(uint256 repayAmount) public {
        if (repayAmount == 0 || s_userBorrowed[msg.sender] < repayAmount) {
            revert Lending__InvalidAmount();
        }
        s_userBorrowed[msg.sender] -= repayAmount;

        bool success = i_corn.transferFrom(msg.sender, address(this), repayAmount);
        if (!success) {
            revert Lending__RepayingFailed();
        }

        emit AssetRepaid(msg.sender, repayAmount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows liquidators to liquidate unsafe positions
     * @param user The address of the user to liquidate
     * @dev The caller must have enough CORN to pay back user's debt
     * @dev The caller must have approved this contract to transfer the debt
     */
    function liquidate(address user) public {
        if (!isLiquidatable(user)) {
            revert Lending__NotLiquidatable(); // Revert if position is not liquidatable
        }

        uint256 userDebt = s_userBorrowed[user]; // Get user's borrowed amount

        if (i_corn.balanceOf(msg.sender) < userDebt) {
            revert Lending__InsufficientLiquidatorCorn();
        }

        uint256 userCollateral = s_userCollateral[user]; // Get user's collateral balance
        uint256 collateralValue = calculateCollateralValue(user); // Calculate user's collateral value

        // transfer value of debt to the contract
        i_corn.transferFrom(msg.sender, address(this), userDebt);

        // Clear user's debt
        s_userBorrowed[user] = 0;

        // calculate collateral to purchase (maintain the ratio of debt to collateral value)
        // collateralValue has 36 decimals, so we multiply by 1e18 to maintain precision
        uint256 collateralPurchased = (userDebt * userCollateral * 1e18) / collateralValue;
        uint256 liquidatorReward = (collateralPurchased * LIQUIDATOR_REWARD) / 100;
        uint256 amountForLiquidator = collateralPurchased + liquidatorReward;
        amountForLiquidator = amountForLiquidator > userCollateral ? userCollateral : amountForLiquidator; // Ensure we don't exceed user's collateral

        s_userCollateral[user] = userCollateral - amountForLiquidator;

        // transfer 110% of the collateral needed to cover the debt to the liquidator
        (bool success,) = payable(msg.sender).call{ value: amountForLiquidator }("");
        if (!success) {
            revert Lending__TransferFailed();
        }

        emit Liquidation(user, msg.sender, amountForLiquidator, userDebt, i_cornDEX.currentPrice());
    }

    /**
     * @notice Returns the maximum amount of CORN that can be borrowed given an ETH deposit
     * @param ethAmount The amount of ETH to deposit as collateral
     * @return uint256 The maximum amount of CORN that can be borrowed
     */
    function getMaxBorrowAmount(uint256 ethAmount) public view returns (uint256) {
        uint256 collateralValue = ethAmount * i_cornDEX.currentPrice();
        return (collateralValue * 100) / COLLATERAL_RATIO;
    }

    /**
     * @notice Returns the maximum amount of ETH collateral that can be withdrawn without liquidation
     * @param user The address of the user to query
     * @return uint256 The amount of ETH that can be safely withdrawn
     */
    function getMaxWithdrawableCollateral(address user) public view returns (uint256) {
        uint256 borrowed = s_userBorrowed[user];
        if (borrowed == 0) {
            return s_userCollateral[user];
        }
        uint256 currentPrice = i_cornDEX.currentPrice();
        uint256 minCollateralValue = (borrowed * COLLATERAL_RATIO) / 100;
        uint256 minCollateral = minCollateralValue / currentPrice;
        uint256 userCollateral = s_userCollateral[user];
        if (userCollateral <= minCollateral) {
            return 0;
        }
        return userCollateral - minCollateral;
    }

    /**
     * @notice Allows users to borrow any amount of CORN as long as it's paid back in the same transaction
     * @param _recipient The contract that will receive the flash loan and execute operations
     * @param _amount The amount of CORN to flash loan
     * @param _extraParam Extra parameter to pass to the recipient (e.g., borrower address for liquidation)
     */
    function flashLoan(IFlashLoanRecipient _recipient, uint256 _amount, address _extraParam) public {
        // Transfer CORN to the recipient
        bool transferSuccess = i_corn.transfer(address(_recipient), _amount);
        if (!transferSuccess) {
            revert Lending__TransferFailed();
        }

        // Call executeOperation on the recipient and verify it returns true
        bool operationSuccess = _recipient.executeOperation(_amount, msg.sender, _extraParam);
        require(operationSuccess, "Flash loan operation failed");

        // Retrieve the CORN back from the recipient
        bool repaySuccess = i_corn.transferFrom(address(_recipient), address(this), _amount);
        if (!repaySuccess) {
            revert Lending__TransferFailed();
        }
    }
}

/**
 * @notice Interface for flash loan recipients
 * @dev Contracts that want to receive flash loans must implement this interface
 */
interface IFlashLoanRecipient {
    /**
     * @notice Called by the Lending contract after sending the flash loaned tokens
     * @param amount The amount of CORN that was flash loaned
     * @param initiator The address that initiated the flash loan
     * @param extraParam Extra parameter passed by the initiator
     * @return bool True if the operation was successful
     */
    function executeOperation(uint256 amount, address initiator, address extraParam) external returns (bool);
}