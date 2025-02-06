// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

abstract contract ServerControlled {
    /// @dev The boolean indicating whether the server is enabled.
    bool public serverEnabled;

    /// @dev Authorized server address.
    address public authorizedServer;

    /// @dev Error: Server disabled.
    error ServerDisabled();

    /// @dev Error: Server enabled.
    error ServerEnabled();

    /// @dev Error: Not authorized server.
    error ENotAuthorizedServer();

    /// @dev Modifier that checks whether the server is enabled.
    modifier serverIsEnabled() {
        if (!serverEnabled) {
            revert ServerDisabled();
        }
        _;
    }

    /// @dev Modifier that checks whether the server is disabled.
    modifier serverIsDisabled() {
        if (serverEnabled) {
            revert ServerEnabled();
        }
        _;
    }

    /// @dev Modifier to check whether the caller is the authorized server.
    modifier onlyAuthorizedServer() {
        if (msg.sender != authorizedServer) {
            revert ENotAuthorizedServer();
        }
        _;
    }

    /**
     * @dev Initializes the contract setting the authorized server address.
     * @param server Authorized server address.
     */
    constructor(address server) {
        authorizedServer = server;
    }

    /**
     * @dev Sets the server enable status.
     * @param enable Server enable status.
     */
    function setServerEnable(bool enable) external virtual;

    /**
     * @dev Set the authorized server address.
     * @param server Authorized server address.
     */
    function setAuthorizedServer(address server) external virtual;
}
