// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMoleculaPool} from "./interfaces/IMoleculaPool.sol";
import {ISupplyManager} from "./interfaces/ISupplyManager.sol";
import {ZeroValueChecker} from "../common/ZeroValueChecker.sol";

/**
 * @dev Token parameters.
 * @param pool Token address.
 * @param n Normalization to 18 decimals: equal to the `18 - poolToken.decimals` value.
 */
struct TokenParams {
    address pool;
    int8 n;
}

/**
 * @dev Token information.
 * @param exist Existence of the pool.
 * @param n Normalization to 18 decimals: equal to the `18 - poolToken.decimals` value.
 */
struct TokenInfo {
    bool exist;
    int8 n;
}

/// @notice MoleculaPool
contract MoleculaPool is Ownable, IMoleculaPool, ZeroValueChecker {
    using SafeERC20 for IERC20;

    /// @dev Pool keeper address.
    address public poolKeeper;

    /// @dev Value to redeem.
    uint256 public valueToRedeem;

    /// @dev List of ERC20 pools.
    TokenParams[] public pools20;

    /// @dev Mapping of ERC20 pools.
    mapping(address => TokenInfo) public pools20Map;

    /// @dev List of ERC4626 pools.
    TokenParams[] public pools4626;

    /// @dev Mapping of ERC20 pools.
    mapping(address => TokenInfo) public pools4626Map;

    /// @dev Supply Manager's address.
    address public immutable SUPPLY_MANAGER;

    /// @dev Authorized redeemer.
    address public authorizedRedeemer;

    /// @dev Error: Not ERC20 token pool.
    error ENotERC20PoolToken();

    /// @dev Error: Provided array is empty.
    error EEmptyArray();

    /// @dev Error: Not authorized redeemer.
    error ENotAuthorizedRedeemer();

    /// @dev Error: Duplicated token.
    error EDuplicatedToken();

    /// @dev Error: Bad index.
    error EBadIndex();

    /// @dev Error: Removed token does not have the zero balance.
    error ENotZeroBalanceOfRemovedToken();

    /**
     * @dev Throws an error if called with the wrong Supply Manager.
     */
    modifier onlySupplyManager() {
        if (msg.sender != SUPPLY_MANAGER) {
            revert ENotMySupplyManager();
        }
        _;
    }

    /**
     * @dev Modifier to check whether the caller is the authorized redeemer.
     */
    modifier onlyAuthorizedRedeemer() {
        if (msg.sender != authorizedRedeemer) {
            revert ENotAuthorizedRedeemer();
        }
        _;
    }

    /**
     * @dev Initializes the contract setting the initializer address.
     * @param initialOwner Owner address.
     * @param authorizedRedeemerAddress Authorized redeemer address.
     * @param p20 List of ERC20 pools.
     * @param p4626 List of ERC4626 pools.
     * @param poolKeeperAddress Pool keeper address.
     * @param supplyManagerAddress Supply Manager's address.
     */
    constructor(
        address initialOwner,
        address authorizedRedeemerAddress,
        TokenParams[] memory p20,
        TokenParams[] memory p4626,
        address poolKeeperAddress,
        address supplyManagerAddress
    )
        Ownable(initialOwner)
        checkNotZero(initialOwner)
        checkNotZero(authorizedRedeemerAddress)
        checkNotZero(poolKeeperAddress)
        checkNotZero(supplyManagerAddress)
    {
        for (uint256 i = 0; i < p20.length; i++) {
            _addToken(p20[i].pool, p20[i].n, pools20, pools20Map);
        }
        for (uint256 i = 0; i < p4626.length; i++) {
            _addToken(p4626[i].pool, p4626[i].n, pools4626, pools4626Map);
        }
        poolKeeper = poolKeeperAddress;
        SUPPLY_MANAGER = supplyManagerAddress;
        authorizedRedeemer = authorizedRedeemerAddress;
    }

    /**
     * @dev Normalizes the value.
     * @param n Normalization to 18 decimals: equal to the `18 - poolToken.decimals` value.
     * @param value Value to normalize.
     * @return result Normalized value.
     */
    function _normalize(int8 n, uint256 value) internal pure returns (uint256 result) {
        uint256 multiplier;
        if (n > 0) {
            multiplier = 10 ** uint256(uint8(n));
            result = value * multiplier;
        } else if (n < 0) {
            multiplier = 10 ** uint256(uint8(-n));
            result = value / multiplier;
        } else {
            // n == 0.
            result = value;
        }
        return result;
    }

    /**
     * @dev Returns the total supply of the ERC20 pools (TVL).
     * @return res Total pool supply.
     */
    function totalPools20Supply() public view returns (uint256 res) {
        uint256 pools20Length = pools20.length;
        for (uint256 i = 0; i < pools20Length; i++) {
            uint256 balance = IERC20(pools20[i].pool).balanceOf(poolKeeper);
            res += _normalize(pools20[i].n, balance);
        }
    }

    /**
     * @dev Returns the total supply of the ERC20 pools (TVL).
     * @return res Total pool supply.
     */
    function totalPools4626Supply() public view returns (uint256 res) {
        uint256 length = pools4626.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 balance = IERC4626(pools4626[i].pool).balanceOf(poolKeeper);
            balance = IERC4626(pools4626[i].pool).convertToAssets(balance);
            res += _normalize(pools4626[i].n, balance);
        }
    }

    /**
     * @inheritdoc IMoleculaPool
     */
    function totalSupply() public view returns (uint256 res) {
        res = totalPools20Supply() + totalPools4626Supply() - valueToRedeem;
    }

    /**
     * @dev Add the value to the pools.
     * @param token ERC20 token address.
     * @param n Decimal normalization.
     * @param pools List of tokens.
     * @param poolsMap Mapping of tokens.
     */
    function _addToken(
        address token,
        int8 n,
        TokenParams[] storage pools,
        mapping(address => TokenInfo) storage poolsMap
    ) internal {
        if (poolsMap[token].exist) {
            revert EDuplicatedToken();
        }
        pools.push(TokenParams(token, n));
        poolsMap[token] = TokenInfo(true, n);
    }

    /**
     * @dev Add the value to the pools.
     * @param token ERC20 token address.
     * @param n Decimal normalization.
     */
    function addPool20(address token, int8 n) external onlyOwner {
        _addToken(token, n, pools20, pools20Map);
    }

    /**
     * @dev Sets the value to the pools.
     * @param i Token index.
     * @param token ERC20 token address.
     * @param n Decimal normalization.
     * @param pools List of tokens.
     * @param poolsMap Mapping of tokens.
     */
    function _setToken(
        uint256 i,
        address token,
        int8 n,
        TokenParams[] storage pools,
        mapping(address => TokenInfo) storage poolsMap
    ) internal {
        if (poolsMap[token].exist) {
            revert EDuplicatedToken();
        }
        if (i >= pools.length) {
            revert EBadIndex();
        }
        delete poolsMap[pools[i].pool];
        pools[i] = TokenParams(token, n);
        poolsMap[token] = TokenInfo(true, n);
    }

    /**
     * @dev Sets the value to the pools.
     * @param i Token index.
     * @param token ERC20 token address.
     * @param n Decimal normalization.
     */
    function setPool20(uint256 i, address token, int8 n) external onlyOwner {
        _setToken(i, token, n, pools20, pools20Map);
    }

    /**
     * @dev Delete the last value from the pools.
     * @param i Token index.
     * @param pools List of tokens.
     * @param poolsMap Mapping of tokens.
     */
    function _removeToken(
        uint256 i,
        TokenParams[] storage pools,
        mapping(address => TokenInfo) storage poolsMap
    ) internal {
        if (i >= pools.length) {
            revert EBadIndex();
        }

        address token = pools[i].pool;

        uint256 balance = IERC20(token).balanceOf(poolKeeper);
        if (balance > 0) {
            revert ENotZeroBalanceOfRemovedToken();
        }

        delete poolsMap[token];
        pools[i] = pools[pools.length - 1];
        pools.pop();
    }

    /**
     * @dev Delete the last value from the pools.
     * @param i Token index.
     */
    function removePool20(uint256 i) external onlyOwner {
        _removeToken(i, pools20, pools20Map);
    }

    /**
     * @dev Add the value to the pools.
     * @param token ERC4626 token address.
     * @param n Decimal normalization.
     */
    function addPool4626(address token, int8 n) external onlyOwner {
        _addToken(token, n, pools4626, pools4626Map);
    }

    /**
     * @dev Sets the value to the pools.
     * @param i ERC4626 token index.
     * @param token ERC4626 token address.
     * @param n Decimal normalization.
     */
    function setPool4626(uint256 i, address token, int8 n) external onlyOwner {
        _setToken(i, token, n, pools4626, pools4626Map);
    }

    /**
     * @dev Delete the last value from the pools.
     * @param i Token index.
     */
    function removePool4626(uint256 i) external onlyOwner {
        _removeToken(i, pools4626, pools4626Map);
    }

    /**
     * @dev Sets the Pool Keeper's wallet.
     * @param poolKeeperAddress Pool Keeper's wallet.
     */
    function setPoolKeeper(
        address poolKeeperAddress
    ) external onlyOwner checkNotZero(poolKeeperAddress) {
        poolKeeper = poolKeeperAddress;
    }

    /**
     * @inheritdoc IMoleculaPool
     */
    function deposit(
        address token,
        uint256 requestId,
        address from,
        uint256 value
    ) external onlySupplyManager returns (uint256 formattedValue) {
        requestId;
        if (pools20Map[token].exist) {
            formattedValue = _normalize(pools20Map[token].n, value);
        } else if (pools4626Map[token].exist) {
            uint256 assets = IERC4626(token).convertToAssets(value);
            formattedValue = _normalize(pools4626Map[token].n, assets);
        } else {
            revert ENotERC20PoolToken();
        }
        // Transfer assets to the Pool keeper.
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(token).safeTransferFrom(from, poolKeeper, value);
        return formattedValue;
    }

    /// @inheritdoc IMoleculaPool
    function requestRedeem(
        address token,
        uint256 value
    ) external onlySupplyManager returns (uint256 formattedValue) {
        if (pools20Map[token].exist) {
            // We receive the value with 18 mUSD decimals.
            // Must reduce the pool amount to correctly calculate `totalSupply` upon redemption.
            valueToRedeem += value;

            // Normalize tokens from 18 mUSD decimals to the ERC20 decimals.
            // Return the value with token decimals for the future `transferFrom` call.
            return _normalize(-pools20Map[token].n, value);
        } else if (pools4626Map[token].exist) {
            // We receive the value with 18 mUSD decimals.
            // Must reduce the pool amount to correctly calculate `totalSupply` upon redemption.
            valueToRedeem += value;

            // Normalize tokens from 18 mUSD decimals to the ERC20 decimals.
            // Return the value converted to shares with token decimals for the future `transferFrom` call.
            uint256 assets = _normalize(-pools4626Map[token].n, value);
            return IERC4626(token).convertToShares(assets);
        } else {
            revert ENotERC20PoolToken();
        }
    }

    /**
     * @dev Redeem tokens.
     * @param requestIds Request IDs.
     */
    function redeem(uint256[] memory requestIds) external payable onlyAuthorizedRedeemer {
        if (requestIds.length == 0) {
            revert EEmptyArray();
        }
        // Call the Supply Manager's `redeem` method.
        // Receive the corresponding ERC20 token and total value redeemed.
        // slither-disable-next-line reentrancy-benign
        (address token, uint256 value) = ISupplyManager(SUPPLY_MANAGER).redeem{value: msg.value}(
            poolKeeper,
            requestIds
        );

        // Normalize the ERC20 token decimals to 18 mUSD decimals.
        // Reduce the value to redeem for correct `totalSupply` calculation.
        valueToRedeem -= _normalize(pools20Map[token].n, value);
    }

    /**
     * @dev Returns the list of ERC20 pools.
     * @return result List of ERC20 pools.
     */
    function getPools20() external view returns (TokenParams[] memory result) {
        return pools20;
    }

    /**
     * @dev Returns the list of ERC4626 pools.
     * @return result List of ERC4626 pools.
     */
    function getPools4626() external view returns (TokenParams[] memory result) {
        return pools4626;
    }

    /**
     * @dev Set the authorized redeemer address.
     * @param authorizedRedeemerAddress Authorized redeemer address.
     */
    function setAuthorizedRedeemer(
        address authorizedRedeemerAddress
    ) external onlyOwner checkNotZero(authorizedRedeemerAddress) {
        authorizedRedeemer = authorizedRedeemerAddress;
    }

    /// @inheritdoc IMoleculaPool
    // solhint-disable-next-line no-empty-blocks
    function setAgent(address /*agent*/, bool /*auth*/) external override onlySupplyManager {
        // Do nothing.
    }

    /// @inheritdoc IMoleculaPool
    // solhint-disable-next-line no-empty-blocks
    function migrate(address oldMoleculaPool) external {
        // Do nothing.
    }
}
