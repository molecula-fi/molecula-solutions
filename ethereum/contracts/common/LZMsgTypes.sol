// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

abstract contract LZMsgTypes {
    /// @dev Constant for requesting the deposit.
    uint8 public constant REQUEST_DEPOSIT = 0x01;
    /// @dev Constant for confirming the deposit.
    uint8 public constant CONFIRM_DEPOSIT = 0x02;
    /// @dev Constant for requesting the redeem operation.
    uint8 public constant REQUEST_REDEEM = 0x03;
    /// @dev Constant for confirming the redeem operation.
    uint8 public constant CONFIRM_REDEEM = 0x04;
    /// @dev Constant for distributing the yield.
    uint8 public constant DISTRIBUTE_YIELD = 0x05;
    /// @dev Constant for confirming the deposit and updating the oracle data.
    uint8 public constant CONFIRM_DEPOSIT_AND_UPDATE_ORACLE = 0x06;
    /// @dev Constant for distributing the yield and updating the oracle data.
    uint8 public constant DISTRIBUTE_YIELD_AND_UPDATE_ORACLE = 0x07;
    /// @dev Constant for updating the oracle data.
    uint8 public constant UPDATE_ORACLE = 0x08;
    /// @dev Constant for swapping USDT for WMUSDT.
    uint8 public constant SWAP_USDT = 0x09;
    /// @dev Constant for swapping WMUSDT for USDT.
    uint8 public constant SWAP_WMUSDT = 0x0a;
}
