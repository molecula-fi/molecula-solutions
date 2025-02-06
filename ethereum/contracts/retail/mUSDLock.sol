// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22; // Make files compatible between the solutions.

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./RebaseERC20.sol";

enum LockState {
    NotExist,
    Active,
    NotActive
}

struct LockInfo {
    address user;
    uint256 shares;
    LockState state;
}

contract MUSDLock {
    using SafeERC20 for RebaseERC20;

    /// @dev Address of the mUSD token.
    RebaseERC20 private immutable _MUSD;

    /// @dev Nonce that is used for generating the lock ID.
    uint256 private _nonce;

    /// @dev Mapping that associates a unique `lockId` with its corresponding `LockInfo` details.
    mapping(bytes32 lockId => LockInfo) public locks;

    /// @dev Mapping that links the user's address to an array of their associated `lockId`'s.
    mapping(address user => bytes32[] lockId) public lockIds;

    /**
     * @dev Emits when the user locks mUSD tokens.
     * @param lockId Lock ID.
     * @param payload Custom payload.
     */
    event Lock(bytes32 lockId, bytes payload);

    /**
     * @dev Emits when the user unlocks the mUSD tokens.
     * @param lockId Lock ID.
     * @param payload Custom payload.
     */
    event Unlock(bytes32 lockId, bytes payload);

    /// @dev An error to throw when the user wants to lock an insufficient value: `value => shares == 0`.
    error ETooSmallValue();

    /// @dev An error to throw when the shares are already unlocked.
    error ESharesAlreadyUnlocked();

    /// @dev An error to throw when the Lock ID doesn't exist.
    error ELockIdNotExist();

    /// @dev An error to throw when having the wrong sender.
    error EWrongSender();

    constructor(RebaseERC20 mUSD_) {
        _MUSD = mUSD_;
    }

    /**
     * @dev Returns an array of the locked user's shares.
     * @param user User address.
     * @return lockIds Array of the locked user's shares.
     */
    function getLockIds(address user) external view returns (bytes32[] memory) {
        return lockIds[user];
    }

    /**
     * @dev Generate a lock ID.
     * @return id Lock ID.
     */
    function _generateLockId() internal returns (bytes32 id) {
        return keccak256(abi.encodePacked(block.prevrandao, _nonce++));
    }

    /**
     * @dev Locks the user's mUSD.
     * @param value Amount of the mUSD tokens.
     * @return lockId Lock ID.
     * @param payload Custom payload.
     */
    function lock(uint256 value, bytes memory payload) external returns (bytes32 lockId) {
        _MUSD.safeTransferFrom(msg.sender, address(this), value);

        uint256 shares = _MUSD.convertToShares(value);
        if (shares == 0) {
            revert ETooSmallValue();
        }

        lockId = _generateLockId();

        locks[lockId] = LockInfo({user: msg.sender, shares: shares, state: LockState.Active});
        lockIds[msg.sender].push(lockId);

        emit Lock(lockId, payload);
    }

    /**
     * @dev Unlocks the user's mUSD tokens.
     * @param lockId Lock ID.
     * @param payload Custom payload.
     */
    function unlock(bytes32 lockId, bytes memory payload) external {
        LockInfo storage userLock = locks[lockId];

        if (userLock.state == LockState.NotExist) {
            revert ELockIdNotExist();
        }
        if (userLock.state == LockState.NotActive) {
            revert ESharesAlreadyUnlocked();
        }
        userLock.state = LockState.NotActive;

        if (userLock.user != msg.sender) {
            revert EWrongSender();
        }

        uint256 asset = _MUSD.convertToAssets(userLock.shares);

        _MUSD.safeTransfer(msg.sender, asset);

        emit Unlock(lockId, payload);
    }
}
