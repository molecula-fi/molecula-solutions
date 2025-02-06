// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @notice Molecula Pool interface
interface IMoleculaPool {
    /// @dev Emitted when Molecula Pool is called with not my Supply Manager.
    error ENotMySupplyManager();

    /**
     * @dev Deposit assets to the pool.
     * @param token Token from pool address.
     * @param requestId Deposit operation unique identifier.
     * @param from From address.
     * @param value Deposit amount.
     * @return formattedValue Formatted deposit amount
     */
    function deposit(
        address token,
        uint256 requestId,
        address from,
        uint256 value
    ) external returns (uint256 formattedValue);

    /**
     * @dev Returns the total supply of the pool (TVL).
     * @return res Total pool supply.
     */
    function totalSupply() external view returns (uint256 res);

    /**
     * @dev Execute the redeem operation request.
     * @param token Token ERC20 from the pool address.
     * @param value Redeem the value.
     * @return formattedValue Formatted redeem operation value.
     */
    function requestRedeem(address token, uint256 value) external returns (uint256 formattedValue);

    /**
     * @dev Authorizes a new Agent.
     * @param agent Agent's address.
     * @param auth Boolean flag indicating whether the Agent is authorized.
     */
    function setAgent(address agent, bool auth) external;

    /// @dev Migrates the state, token pools, and configurations from an old Molecula Pool contract to the new one.
    /// @param oldMoleculaPool Old Molecula Pool's address.
    function migrate(address oldMoleculaPool) external;
}
