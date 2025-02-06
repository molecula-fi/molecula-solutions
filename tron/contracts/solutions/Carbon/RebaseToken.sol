// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {RebaseTokenCommon} from "@molecula-monorepo/ethereum/contracts/retail/RebaseTokenCommon.sol";

contract RebaseToken is RebaseTokenCommon {
    /**
     * @dev Constructor for initializing the contract.
     * @param initialOwner Smart contract owner address.
     * @param accountantAddress Accountant address.
     * @param initialShares Shares' amount to mint.
     * @param oracleAddress Oracle contract address.
     * @param tokenName Token name.
     * @param tokenSymbol Token symbol.
     * @param tokenDecimals Token decimals.
     * @param minDeposit Minimum deposit value.
     * @param minRedeem Minimum redeem operation value.
     */
    constructor(
        address initialOwner,
        address accountantAddress,
        uint256 initialShares,
        address oracleAddress,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        uint256 minDeposit,
        uint256 minRedeem
    )
        RebaseTokenCommon(
            initialOwner,
            accountantAddress,
            initialShares,
            oracleAddress,
            tokenName,
            tokenSymbol,
            tokenDecimals,
            minDeposit,
            minRedeem
        )
    {}
}
