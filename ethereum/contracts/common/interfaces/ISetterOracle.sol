// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {IOracle} from "./IOracle.sol";

interface ISetterOracle is IOracle {
    /**
     * @dev Sets the total pool supply value into the contract.
     * @param pool Total pool supply value.
     */
    function setTotalPoolSupply(uint256 pool) external;

    /**
     * @dev Sets the total shares' supply value into the contract.
     * @param shares Total shares' supply value.
     */
    function setTotalSharesSupply(uint256 shares) external;

    /**
     * @dev Sets the total pool and shares' supply value into the contract.
     * @param pool Total pool supply value.
     * @param shares Total shares' supply value.
     */
    function setTotalSupply(uint256 pool, uint256 shares) external;
}
