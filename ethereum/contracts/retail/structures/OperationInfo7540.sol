// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {OperationStatus} from "./OperationStatus.sol";

/**
 * @dev Struct to store the deposit information.
 * @param addr User address associated with the operation.
 * @param assets Operation-associated token amount on deposit.
 * @param status Operation status.
 */
struct DepositOperationInfo {
    address addr;
    uint256 assets;
    OperationStatus status;
}

/**
 * @dev Struct to store the redeem operation information.
 * @param addr User address associated with the operation.
 * @param val Operation-associated value on the withdrawal.
 * @param status Operation status.
 */
struct RedeemOperationInfo {
    address addr;
    uint256 val;
    OperationStatus status;
}
