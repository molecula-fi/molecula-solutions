// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

interface IOracle {
    /**
     * @dev Reads the total pool supply value from the contract.
     * @return pool Total pool supply value.
     */
    function getTotalPoolSupply() external view returns (uint256 pool);

    /**
     * @dev Reads the total shares' supply value from the contract.
     * @return shares Total shares' supply value.
     */
    function getTotalSharesSupply() external view returns (uint256 shares);

    /**
     * @dev Reads the total supply value from the contract.
     * @return pool Total pool supply value.
     * @return shares Total shares' supply value.
     */
    function getTotalSupply() external view returns (uint256 pool, uint256 shares);
}
