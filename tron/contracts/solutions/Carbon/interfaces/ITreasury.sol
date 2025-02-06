// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

interface ITreasury {
    /**
     * @dev Locks tokens for the redemption.
     * @param totalValue Total value to redeem.
     */
    function redeem(uint256 totalValue) external;
    /**
     * @dev Confirms the redemption.
     * @param user User address.
     * @param value Value to redeem.
     */
    function confirmRedeem(address user, uint256 value) external;
}
