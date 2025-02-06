// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

enum OperationStatus {
    None,
    Pending,
    Confirmed,
    Reverted,
    ReadyToConfirm
}
