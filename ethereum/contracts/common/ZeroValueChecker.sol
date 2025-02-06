// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

contract ZeroValueChecker {
    /// @dev Error: msg.value is not equal to zero.
    error EMsgValueIsNotZero();

    /**
     * @dev Modifier that checks whether msg.value is equal to zero.
     */
    modifier onlyZeroMsgValue() {
        if (msg.value != 0) {
            revert EMsgValueIsNotZero();
        }
        _;
    }

    /// @dev Error: Zero address.
    error EZeroAddress();

    /**
     * @dev Modifier that checks whether `addr` is the zero address.
     * @param addr Address.
     */
    modifier checkNotZero(address addr) {
        if (addr == address(0)) {
            revert EZeroAddress();
        }
        _;
    }
}
