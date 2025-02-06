// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @notice Agent interface
interface IAgent {
    /**
     * @dev Emitted when processing deposits.
     * @param requestId Deposit operation unique identifier.
     * @param value A deposited amount.
     * @param shares Shares' amount to mint.
     */
    event Deposit(uint256 indexed requestId, uint256 value, uint256 shares);

    /**
     * @dev Emitted when confirming deposits.
     * @param requestId Deposit operation unique identifier.
     * @param shares Shares' amount to mint.
     */
    event DepositConfirm(uint256 indexed requestId, uint256 shares);

    /**
     * @dev Event emitted when a user processes a redeem operation.
     * @param requestId Withdrawal operation unique identifier.
     * @param shares Withdrawal operation shares.
     * @param value Withdrawal operation value.
     */
    event RedeemRequest(uint256 requestId, uint256 shares, uint256 value);

    /**
     * @dev Event emitted when distributing yield.
     * @param users Array of user addresses.
     * @param shares Array of shares.
     */
    event DistributeYield(address[] users, uint256[] shares);

    /**
     * @dev Redeems the funds.
     * @param fromAddress Address to redeem from.
     * @param requestIds Array of redeem operation IDs.
     * @param values Array of values to redeem.
     * @param totalValue Total value to redeem.
     */
    function redeem(
        address fromAddress,
        uint256[] memory requestIds,
        uint256[] memory values,
        uint256 totalValue
    ) external payable;

    /**
     * @dev Returns the ERC20 token address.
     * @return token ERC20 token address.
     */
    function getERC20Token() external view returns (address token);

    /**
     * @dev Adds shares to the user.
     * @param users User's address.
     * @param shares Amount of shares to add.
     */
    function distribute(address[] memory users, uint256[] memory shares) external payable;
}
