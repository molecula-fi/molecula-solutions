// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22; // Make files compatible between the solutions.

interface IRebaseTokenErrors {
    /// @dev Error to throw if an operation is called with invalid parameters.
    error EBadOperationParameters();

    /// @dev Error to throw if the `owner` isn't the sender and `msg.sender` isn't the owner's operator.
    /// @param sender Message sender.
    /// @param owner Beneficiary of the deposit request.
    error EBadOwner(address sender, address owner);

    /**
     * @dev Emitted when the deposit value is less than the `depositValue` value.
     * @param depositValue Minimal deposit value.
     */
    error ETooLowDepositValue(uint256 depositValue);

    /**
     * @dev Emitted when the withdrawal value is less than the `withdrawValue` value.
     * @param redeemValue Minimal withdrawal value.
     */
    error ETooLowRedeemValue(uint256 redeemValue);

    /// @dev Error: Only accountant.
    error EOnlyAccountant();

    /// @dev Emitted when trying set `minDepositValue` to zero.
    error EZeroMinDepositValue();

    /// @dev Emitted when trying set `minRedeemValue` to zero.
    error EZeroMinRedeemValue();
}
