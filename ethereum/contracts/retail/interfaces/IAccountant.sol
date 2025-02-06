// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

/// @notice IAccountant
interface IAccountant {
    /**
     * @dev Requests a deposit.
     * @param requestId Deposit operation unique identifier.
     * @param user User's address.
     * @param value Amount to deposit.
     */
    function requestDeposit(uint256 requestId, address user, uint256 value) external payable;

    /**
     * @dev Confirms a redemption.
     * @param user User's address.
     * @param value Amount to confirm.
     */
    function confirmRedeem(address user, uint256 value) external;

    /**
     * @dev Requests the redeem operation.
     * @param requestId Redeem operation ID.
     * @param shares Shares to redeem.
     */
    function requestRedeem(uint256 requestId, uint256 shares) external payable;
}
