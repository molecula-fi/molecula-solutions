// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStakedUSDeV2} from "./interfaces/IStakedUSDeV2.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title mUSDe token for only one user.
contract MUSDE is IERC20Metadata, Ownable {
    using SafeERC20 for IStakedUSDeV2;

    /// @dev sUSDe contract address.
    /// @custom:security non-reentrant
    IStakedUSDeV2 private immutable _STAKED_USDE_V2;

    /// @dev Balance of `owner()`.
    uint256 private _balance;

    /// @dev Error: Unsupported operation.
    error EUnsupportedOperation();

    /// @dev Error: sUSDe contract has no cooldown period.
    error ENoCooldown();

    /**
     * @dev Emitted when mUSDe tokens were minted.
     * @param owner Address of the token user.
     * @param mUSDeAmount Amount of shares to mint.
     */
    event Mint(address indexed owner, uint256 mUSDeAmount);

    /**
     * @dev Emitted when mUSDe tokens were burnt.
     * @param owner Address of the token user.
     * @param mUSDeAmount Amount of shares to burn.
     */
    event Burn(address indexed owner, uint256 mUSDeAmount);

    /**
     * @dev Constructor for initializing the contract.
     * @param stakedUSDeV2Addr sUSDe contract address.
     * @param initialOwner mUSDe contract's owner address.
     */
    constructor(IStakedUSDeV2 stakedUSDeV2Addr, address initialOwner) Ownable(initialOwner) {
        _STAKED_USDE_V2 = stakedUSDeV2Addr;
    }

    /**
     * @dev Returns the name of the token.
     * @return The name of the token.
     */
    function name() public view virtual returns (string memory) {
        return "Molecula USDe";
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     * @return The symbol of the token.
     */
    function symbol() public view virtual returns (string memory) {
        return "mUSDe";
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * @return The number of decimals.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev Returns the value of tokens owned by `account`.
     * @param account Address of account.
     * @return The value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256) {
        return account == owner() ? _balance : 0;
    }

    /**
     * @dev Returns the value of tokens in existence.
     * @return The value of tokens in existence.
     */
    function totalSupply() external view returns (uint256) {
        return _balance;
    }

    /**
     * @dev {IERC20-transfer} is not supported.
     * @param to Recipient of tokens.
     * @param value Amount of tokens.
     * @return Returns the success flag.
     */
    function transfer(address to, uint256 value) public pure override returns (bool) {
        to;
        value;
        revert EUnsupportedOperation();
    }

    /**
     * @dev {IERC20-allowance} is not supported.
     * @param owner Owner of tokens.
     * @param spender Spender of tokens.
     * @return Returns allowance.
     */
    function allowance(address owner, address spender) public pure override returns (uint256) {
        owner;
        spender;
        revert EUnsupportedOperation();
    }

    /**
     * @dev {IERC20-approve} is not supported.
     * @param spender Grantee of allowance.
     * @param value Amount of tokens.
     * @return Returns the success flag.
     */
    function approve(address spender, uint256 value) public pure override returns (bool) {
        spender;
        value;
        revert EUnsupportedOperation();
    }

    /**
     * @dev {IERC20-transferFrom} is not supported.
     * @param from Sender of tokens.
     * @param to Recipient of tokens.
     * @param value Amount of tokens.
     * @return Returns the success flag.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public pure override returns (bool) {
        from;
        to;
        value;
        revert EUnsupportedOperation();
    }

    /**
     * @dev {Ownable-renounceOwnership} is not supported.
     */
    function renounceOwnership() public pure override {
        revert EUnsupportedOperation();
    }

    /**
     * @dev Move sUSDe from the owner to this contact, burn sUSDe, cooldown UDSe, and mint mUSDe.
     * @param sUSDeAmount Amount of sUSDe tokens to burn.
     */
    function cooldownShares(uint256 sUSDeAmount) public onlyOwner {
        // Check the `cooldownDuration` value.
        // Note: If `cooldownDuration == 0`, we can use `_stakedUSDeV2::redeem()` to burn sUSDe and get USDe in one transaction without minting mUSDe.
        if (_STAKED_USDE_V2.cooldownDuration() == 0) {
            revert ENoCooldown();
        }

        // Move sUSDe tokens from the contract owner to this contract, using the allowance mechanism.
        _STAKED_USDE_V2.safeTransferFrom(msg.sender, address(this), sUSDeAmount);

        // Burn sUSDe and cooldown USDe.
        uint256 usdeAmount = _STAKED_USDE_V2.cooldownShares(sUSDeAmount);

        // Mint mUSDe.
        _balance += usdeAmount;

        // Emit the event to reflect minting the mUSDe tokens equal to `usdeAmount` for the `msg.sender` account.
        emit Mint(msg.sender, usdeAmount);
    }

    /// @dev Unfreeze UDSe and burn mUSDe.
    function unstake() public onlyOwner {
        // Claim USDe after the cooldown has finished.
        _STAKED_USDE_V2.unstake(msg.sender);

        // Emit the event to reflect burning the mUSDe tokens equal to `amount` for the `msg.sender` account.
        emit Burn(msg.sender, _balance);

        // Burn all mUSDe.
        _balance = 0;
    }

    /// @dev Get info about the frozen USDe or sUSDe tokens.
    /// @return cooldownEnd Moment when the cooldown ends and we can unstake sUSDe and get USDe.
    /// @return underlyingAmount Amount of USDe that is frozen.
    /// @return canUnstake Boolean flag indicating whether it is possible to unstake the tokens now.
    function getCooldownInfo()
        public
        view
        returns (uint104 cooldownEnd, uint152 underlyingAmount, bool canUnstake)
    {
        (cooldownEnd, underlyingAmount) = _STAKED_USDE_V2.cooldowns(address(this));
        canUnstake = block.timestamp >= cooldownEnd || _STAKED_USDE_V2.cooldownDuration() == 0;
    }
}
