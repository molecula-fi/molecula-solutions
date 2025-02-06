// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22; // Make files compatible between the solutions.

import {MUSDLock as EthMUSDLock} from "@molecula-monorepo/ethereum/contracts/retail/mUSDLock.sol";
import {RebaseERC20} from "@molecula-monorepo/ethereum/contracts/retail/RebaseERC20.sol";

contract MUSDLock is EthMUSDLock {
    constructor(RebaseERC20 mUSD_) EthMUSDLock(mUSD_) {}
}
