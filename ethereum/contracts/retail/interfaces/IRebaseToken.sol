// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22; // Make files compatible between the solutions.

interface IRebaseToken {
    /**
     * @dev Confirms a deposit.
     * @param operationId Operation ID.
     * @param shares Shares' amount.
     */
    function confirmDeposit(uint256 operationId, uint256 shares) external;

    /**
     * @dev Confirms a redeem operation.
     * @param operationId Operation ID.
     */
    function confirmRedeem(uint256 operationId) external;

    /**
     * @dev Redeem execution.
     * @param requestIds Array of redeem operation IDs.
     * @param values Array of values to redeem.
     * @return totalValue Total value to redeem.
     */
    function redeem(
        uint256[] memory requestIds,
        uint256[] memory values
    ) external returns (uint256 totalValue);

    /**
     * @dev Distributes the reward.
     * @param party User's address.
     * @param shares Amount of shares to add.
     */
    function distribute(address party, uint256 shares) external;
}
