// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22; // Make files compatible between the solutions.

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

import {RebaseERC20} from "./RebaseERC20.sol";

/**
 * @title RebaseERC20Permit
 * @dev Contract for implementing the RebaseERC20 functionality with the EIP-2612 standard's `Permit` function.
 */
contract RebaseERC20Permit is RebaseERC20, IERC20Permit, EIP712, Nonces {
    /// @dev Hashed representation of the `Permit` function signature as a string.
    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    /**
     * @dev The deadline for the `Permit` function has expired.
     * @param deadline Deadline for the signature.
     */
    error ERC2612ExpiredSignature(uint256 deadline);

    /**
     * @dev Mismatched signature.
     * @param signer Signer address.
     * @param owner Owner address.
     */
    error ERC2612InvalidSigner(address signer, address owner);

    /**
     * @dev Constructor for initializing the contract.
     * @param initialShares Shares' amount to mint.
     * @param oracleAddress Oracle contract address.
     * @param initialOwner Smart contract owner address.
     * @param tokenName Token name.
     * @param tokenSymbol Token symbol.
     * @param tokenDecimals Token decimals.
     */
    constructor(
        uint256 initialShares,
        address oracleAddress,
        address initialOwner,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals
    )
        RebaseERC20(
            initialShares,
            oracleAddress,
            initialOwner,
            tokenName,
            tokenSymbol,
            tokenDecimals
        )
        EIP712("RebaseERC20Permit", "1.0.0")
    {}

    /**
     * @inheritdoc IERC20Permit
     */
    function permit(
        address owner,
        address spender,
        uint256 shares,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(
            abi.encode(_PERMIT_TYPEHASH, owner, spender, shares, _useNonce(owner), deadline)
        );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }

        _approve(owner, spender, shares);
    }

    /**
     * @inheritdoc IERC20Permit
     */
    function nonces(
        address owner
    ) public view virtual override(IERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @inheritdoc IERC20Permit
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }
}
