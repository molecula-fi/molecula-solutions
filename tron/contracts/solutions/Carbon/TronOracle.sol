// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// solhint-disable-next-line no-unused-import
import {ISetterOracle, IOracle} from "@molecula-monorepo/ethereum/contracts/common/interfaces/ISetterOracle.sol";

/**
 * @title TronOracle
 * @dev Contract for managing shares and pool information, implementing the IOracle interface.
 */
contract TronOracle is Ownable, ISetterOracle {
    /// @dev Total pool value tracked by the Oracle.
    uint256 private _pool = 0;

    /// @dev Total shares value tracked by the Oracle.
    uint256 private _shares = 0;

    /// @dev Accountant address.
    address public accountant;

    /// @dev Authorized updater address.
    address public authorizedUpdater;

    /// @dev Error: Only owner or Accountant.
    error ENotAuthorizedUpdaterOrAccountant();

    /// @dev Error: Only authorized updater.
    error ENotAuthorizedUpdater();

    /**
     * @dev Modifier that checks whether the caller is the owner or accountant.
     */
    modifier onlyAuthorizedUpdaterOrAccountant() {
        if (msg.sender != authorizedUpdater && msg.sender != accountant) {
            revert ENotAuthorizedUpdaterOrAccountant();
        }
        _;
    }

    /**
     * @dev Modifier to check whether the caller is the value setter.
     */
    modifier onlyAuthorizedUpdater() {
        if (msg.sender != authorizedUpdater) {
            revert ENotAuthorizedUpdater();
        }
        _;
    }

    /**
     * @dev Constructor that initializes the smart contract by setting the initial shares, pool value, and its owner.
     * @param initialShares Shares number to set for the Oracle specified during contract creation.
     * @param initialPool Pool value to set for the Oracle specified during contract creation.
     * @param initialOwner Smart contract owner address.
     * @param accountantAddress Accountant address.
     * @param authorizedUpdaterAddress Value setter address.
     */
    constructor(
        uint256 initialShares,
        uint256 initialPool,
        address initialOwner,
        address accountantAddress,
        address authorizedUpdaterAddress
    ) Ownable(initialOwner) {
        _pool = initialPool;
        _shares = initialShares;
        accountant = accountantAddress;
        authorizedUpdater = authorizedUpdaterAddress;
    }

    /**
     * @inheritdoc ISetterOracle
     */
    function setTotalPoolSupply(uint256 pool) external onlyAuthorizedUpdater {
        _pool = pool;
    }

    /**
     * @inheritdoc ISetterOracle
     */
    function setTotalSharesSupply(uint256 shares) external onlyAuthorizedUpdater {
        _shares = shares;
    }

    /**
     * @inheritdoc ISetterOracle
     */
    function setTotalSupply(
        uint256 pool,
        uint256 shares
    ) external onlyAuthorizedUpdaterOrAccountant {
        _pool = pool;
        _shares = shares;
    }

    /**
     * @inheritdoc IOracle
     */
    function getTotalPoolSupply() external view returns (uint256 pool) {
        return _pool;
    }

    /**
     * @inheritdoc IOracle
     */
    function getTotalSharesSupply() external view returns (uint256 shares) {
        return _shares;
    }

    /**
     * @inheritdoc IOracle
     */
    function getTotalSupply() external view returns (uint256 pool, uint256 shares) {
        return (_pool, _shares);
    }

    /**
     * @dev Setter for the Accountant address.
     * @param accountantAddress New Accountant address.
     */
    function setAccountant(address accountantAddress) external onlyOwner {
        accountant = accountantAddress;
    }

    /**
     * @dev Setter for the Value setter address.
     * @param authorizedUpdaterAddress New Value setter address.
     */
    function setAuthorizedUpdater(address authorizedUpdaterAddress) external onlyOwner {
        authorizedUpdater = authorizedUpdaterAddress;
    }
}
