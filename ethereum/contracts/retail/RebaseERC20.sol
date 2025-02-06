// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22; // Make files compatible between the solutions.

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IOracle} from "../common/interfaces/IOracle.sol";
import {IRebaseERC20} from "./interfaces/IRebaseERC20.sol";
import {ZeroValueChecker} from "../common/ZeroValueChecker.sol";

/**
 * @title RebaseERC20
 * @dev Contract for implementing the RebaseERC20 functionality.
 * The contract leverages:
 * - The Ethereum's ERC20 standard.
 * - The OpenZeppelin's Ownable library.
 * - IOracle and IRebaseERC20 interfaces for Oracle- and YGT token-related functionalities.
 */
contract RebaseERC20 is IRebaseERC20, Ownable, IERC20Metadata, IERC20Errors, ZeroValueChecker {
    /// @dev Mapping of account addresses to their respective token balances.
    mapping(address => uint256) private _shares;

    /// @dev Mapping of account addresses to their respective mapping of spender addresses to token allowances.
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @dev Token name.
    string private _name;

    /// @dev Token symbol.
    string private _symbol;

    /// @dev Token decimals.
    uint8 private _decimals;

    /// @dev Oracle contract address.
    address public oracle;

    /// @dev Tokens contract local total shares.
    uint256 public localTotalShares;

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
    ) Ownable(initialOwner) {
        oracle = oracleAddress;
        _name = tokenName;
        _symbol = tokenSymbol;
        _decimals = tokenDecimals;
        _mint(address(this), initialShares);
    }

    /**
     * @dev Converts assets to shares.
     * @param assets Amount of assets to convert.
     * @return shares Converted amount of shares.
     */
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        (uint256 pool, uint256 poolShares) = IOracle(oracle).getTotalSupply();
        return (assets * poolShares) / pool;
    }

    /**
     * @dev Converts shares to assets.
     * @param shares Amount of shares to convert.
     * @return assets Converted amount of assets.
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        (uint256 pool, uint256 poolShares) = IOracle(oracle).getTotalSupply();
        return (shares * pool) / poolShares;
    }

    /**
     * @dev Returns the total supply of the token (Total Value Locked).
     * @return totalPool Token's total supply (Total Value Locked).
     */
    function totalSupply() public view override returns (uint256 totalPool) {
        totalPool = IOracle(oracle).getTotalPoolSupply();
        return totalPool;
    }

    /**
     * @dev Returns the total supply of the token in shares.
     * @return totalShares Token's total supply in shares.
     */
    function totalSharesSupply() public view returns (uint256 totalShares) {
        totalShares = IOracle(oracle).getTotalSharesSupply();
        return totalShares;
    }

    /**
     * @inheritdoc IRebaseERC20
     */
    function mint(address to, uint256 shares) external onlyOwner {
        _mint(to, shares);
    }

    /**
     * @inheritdoc IRebaseERC20
     */
    function burn(address account, uint256 shares) external onlyOwner {
        _burn(account, shares);
    }

    /**
     * @inheritdoc IRebaseERC20
     */
    function sharesOf(address user) public view returns (uint256 shares) {
        return _shares[user];
    }

    /**
     * @dev Returns the user's balance.
     * @param user User whose balance is to be returned.
     * @return balance User's balance.
     */
    function balanceOf(address user) public view override returns (uint256 balance) {
        return convertToAssets(_shares[user]);
    }

    /**
     * @dev Returns the token's decimals.
     * @return tokenDecimals Token's decimals.
     */
    function decimals() public view override returns (uint8 tokenDecimals) {
        return _decimals;
    }

    /**
     * @dev Transfers the token.
     * @param to Tokens recipient's address.
     * @param value Token amount to transfer.
     * @return result Boolean indicating whether the operation is successful.
     */
    function transfer(address to, uint256 value) public override returns (bool result) {
        address owner = _msgSender();
        uint256 shares = convertToShares(value);
        _transfer(owner, to, shares);
        return true;
    }

    /**
     * @dev Returns the spender's allowance.
     * @param owner Tokens owner.
     * @param spender Tokens spender.
     * @return amount Token amount the spender can expend.
     */
    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256 amount) {
        uint256 allow = _allowances[owner][spender];
        // Note: `type(uint256).max` means an infinite allowance.
        return allow == type(uint256).max ? allow : convertToAssets(allow);
    }

    /**
     * @dev Approves a spender.
     * @param spender Spender to be approved.
     * @param value Token amount the spender can expend.
     * @return result Boolean indicating whether the operation is successful.
     */
    function approve(address spender, uint256 value) public override returns (bool result) {
        address owner = _msgSender();
        // Note: `type(uint256).max` means an infinite allowance.
        uint256 shares = value == type(uint256).max ? value : convertToShares(value);
        _approve(owner, spender, shares);
        return true;
    }

    /**
     * @dev Transfers tokens from one address to another.
     * @param from Sender address.
     * @param to Recipient address.
     * @param value Token amount to transfer.
     * @return result Boolean indicating whether the operation is successful.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool result) {
        address spender = _msgSender();
        uint256 shares = convertToShares(value);
        _spendAllowance(from, spender, shares);
        _transfer(from, to, shares);
        return true;
    }

    /**
     * @dev Returns the name of the token.
     * @return tokenName Token name.
     */
    function name() public view returns (string memory tokenName) {
        return _name;
    }

    /**
     * @dev Returns the token symbol. Usually a shorter version of its name.
     * @return tokenSymbol Token symbol.
     */
    function symbol() public view virtual returns (string memory tokenSymbol) {
        return _symbol;
    }

    /**
     * @dev Moves the `shares` amount of tokens, emitting a {Transfer} event.
     *
     * This internal function is equivalent to {transfer}. For example, it can implement automatic token fees or slashing mechanisms.
     *
     * As this function is not virtual, {_update} should be overridden instead.
     *
     * @param from Tokens owner's address.
     * @param to Tokens recipient's address.
     * @param shares Shares' amount to transfer.
     */
    function _transfer(address from, address to, uint256 shares) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, shares);
    }

    /**
     * @dev Transfers the `shares` amount of tokens. Alternatively, mints or burns the tokens if the token owner or recipient, respectively, is the “zero address“. Emits a {Transfer} event.
     *
     * All customizations to transfers, mints, and burns should be done by overriding this function.
     *
     * @param from Tokens owner's address.
     * @param to Tokens recipient's address.
     * @param shares Shares' amount to transfer.
     */
    function _update(address from, address to, uint256 shares) internal virtual {
        if (from != address(0)) {
            uint256 fromShares = _shares[from];
            if (fromShares < shares) {
                revert ERC20InsufficientBalance(from, fromShares, shares);
            }
            unchecked {
                // Overflow not possible: shares <= fromShares.
                _shares[from] = fromShares - shares;
            }
        }

        if (to != address(0)) {
            // Overflow check required: balance + shares should fit into a uint256.
            _shares[to] += shares;
        }

        // Convert the shares to the relevant value for more proper event emitting.
        uint256 converted = convertToAssets(shares);
        emit Transfer(from, to, converted);
        // Emit the transfer event with the shares value.
        emit TransferShares(from, to, shares);
    }

    /**
     * @dev Creates a `shares` amount of tokens and assigns them to the `account` by transferring the tokens from the “zero address“.
     *
     *  The function relies on the `_update` method and emits a {Transfer} event with the `from` parameter equal to the zero address.
     *
     * @param account Minted tokens recipient's address.
     * @param shares Shares' amount to mint.
     */
    function _mint(address account, uint256 shares) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, shares);
        localTotalShares += shares;
    }

    /**
     * @dev Destroys the `shares` amount of tokens from the `account`, lowering the total supply.
     *
     * Relies on the `_update` mechanism and emits a {Transfer} event.
     *
     * @param account Account address whose tokens are to be burnt.
     * @param shares Shares' amount to be burned.
     */
    function _burn(address account, uint256 shares) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), shares);
        localTotalShares -= shares;
    }
    /**
     * @dev Sets the `shares` as the allowance of the `spender` over the `owner`'s tokens. Emits an {Approval} event.
     *
     * This internal function is equivalent to `approve`. For example, it can be used to set automatic allowances for particular subsystems. Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     *
     * Requirements:
     *
     * - `owner` cannot be the “zero address“.
     * - `spender` cannot be the “zero address“.
     *
     * @param owner Tokens owner's address.
     * @param spender Address, which will be allowed to spend the tokens.
     * @param shares Shares' amount that the address will be allowed to spend.
     */
    function _approve(address owner, address spender, uint256 shares) internal {
        _approve(owner, spender, shares, true);
    }

    /**
     * @dev A variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default, when calling {_approve}, the flag is set to `true`. On the other hand, approval changes made by `_spendAllowance` during the `transferFrom` operation sets the flag to `false`. This saves gas by not emitting any {Approval} event during the `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting {Approval} events on the`transferFrom` operation can force the flag to `true` using the following override:
     * ```
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * Requirements are the same as with {_approve}.
     *
     * @param owner Tokens owner's address.
     * @param spender Address, which will be allowed to spend the tokens.
     * @param shares Shares' amount that the address will be allowed to spend.
     * @param emitEvent Boolean flag indicating whether to emit an {Approval} event.
     */
    function _approve(
        address owner,
        address spender,
        uint256 shares,
        bool emitEvent
    ) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = shares;
        if (emitEvent) {
            // Convert the shares to the relevant value for more proper event emitting.
            // Note: `type(uint256).max` means an infinite allowance.
            uint256 converted = shares == type(uint256).max ? shares : convertToAssets(shares);
            emit Approval(owner, spender, converted);
        }
    }

    /**
     * @dev Updates the `owner`'s allowance for the `spender` based on the spent `shares`. Does not emit an {Approval} event.
     *
     * Does not update the allowance value in case of the infinite allowance. Reverts the operation if not enough allowance is available.
     *
     * @param owner Tokens owner's address.
     * @param spender Address, which will be allowed to spend the tokens.
     * @param shares Shares' amount to spend from the allowance.
     */
    function _spendAllowance(address owner, address spender, uint256 shares) internal virtual {
        uint256 currentAllowance = _allowances[owner][spender];
        // Note: `type(uint256).max` means the infinite allowance
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < shares) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, shares);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - shares, false);
            }
        }
    }

    /**
     * @dev Sets the Oracle contract address.
     * @param oracleAddress Oracle contract address.
     */
    function setOracle(address oracleAddress) public onlyOwner checkNotZero(oracleAddress) {
        oracle = oracleAddress;
    }
}
