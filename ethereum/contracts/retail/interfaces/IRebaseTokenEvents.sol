// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22; // Make files compatible between the solutions.

interface IRebaseTokenEvents {
    /**
     * @dev Emitted when a deposit gets confirmed.
     *
     * @param requestId Operation ID.
     * @param user User's address that deposits.
     * @param assets Deposit amount.
     * @param shares Shares amount.
     */
    event DepositConfirm(uint256 indexed requestId, address user, uint256 assets, uint256 shares);

    /**
     * @dev Emitted when a withdrawal gets confirmed.
     *
     * @param requestId Operation ID.
     * @param user User's address that withdraws.
     * @param assets Withdrawal amount.
     */
    event RedeemConfirm(uint256 indexed requestId, address user, uint256 assets);

    /** @dev Event emitted when a user requests a deposit.
     * @param controller Controller's address.
     * @param owner User's address.
     * @param requestId Operation ID.
     * @param sender Sender's address.
     * @param assets Amount of assets to deposit.
     */
    event DepositRequest(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 assets
    );

    /** @dev Event emitted when a user requests a withdrawal.
     * @param controller Controller's address.
     * @param owner User's address.
     * @param requestId Operation ID.
     * @param sender Sender's address.
     * @param shares Amount of shares to withdraw.
     */
    event RedeemRequest(
        address indexed controller,
        address indexed owner,
        uint256 indexed requestId,
        address sender,
        uint256 shares
    );

    /**
     * @dev Event emitted when an operator is set.
     * @param controller Controller's address.
     * @param operator Operator's address.
     * @param approved Approval status.
     */
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /**
     * @dev Event emitted when redeem requests are ready to be processed.
     * @param requestIds Array of request IDs.
     * @param values Array of corresponding values.
     */
    event Redeem(uint256[] requestIds, uint256[] values);
}
