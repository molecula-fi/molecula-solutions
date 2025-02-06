// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IAgent} from "./interfaces/IAgent.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IMoleculaPool} from "./interfaces/IMoleculaPool.sol";
import {ISupplyManager} from "./interfaces/ISupplyManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
 * @param arrayIndex Index in `TokenParams[] pools`.
 */
struct TokenInfo {
    bool exist;
    int8 n;
    uint32 arrayIndex;
}

/// @notice MoleculaPoolTreasury
contract MoleculaPoolTreasury is Ownable, IMoleculaPool, ZeroValueChecker {
    using SafeERC20 for IERC20;
    using Address for address;

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

    /// @dev Error: Not ERC20 token pool.
    error ENotERC20PoolToken();

    /// @dev Error: Not ERC4626 token pool.
    error ENotERC4626PoolToken();

    /// @dev Error: Provided array is empty.
    error EEmptyArray();

    /// @dev Error: Duplicated token.
    error EDuplicatedToken();

    /// @dev Error: Removed token does not have the zero balance.
    error ENotZeroBalanceOfRemovedToken();

    /// @dev Error: Molecula Pool does not have the token.
    error ETokenNotExist();

    /// @dev Emitted when the Molecula Pool is called by non-PoolKeeper.
    error ENotMyPoolKeeper();

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
     * @dev Throws an error if called with the wrong PoolKeeper.
     */
    modifier onlyPoolKeeper() {
        if (msg.sender != poolKeeper) {
            revert ENotMyPoolKeeper();
        }
        _;
    }

    /// @dev White list of address callable by this contract.
    mapping(address => bool) public isInWhiteList;

    /// @dev Emitted when the target address is not in the white list.
    error ENotInWhiteList();

    /// @dev Emitted when the target address has already been added.
    error EAlreadyAddedInWhiteList();

    /// @dev Emitted when the target address has been deleted or hasn't been added yet.
    error EAlreadyDeletedInWhiteList();

    /**
     * @dev Emitted when the target has been added in the white list.
     * @param target Address.
     */
    event AddedInWhiteList(address indexed target);

    /**
     * @dev Emitted when the target has been deleted from the white list.
     * @param target Address.
     */
    event DeletedFromWhiteList(address indexed target);

    /**
     * @dev Initializes the contract setting the initializer address.
     * @param initialOwner Owner's address.
     * @param p20 List of ERC20 pools.
     * @param p4626 List of ERC4626 pools.
     * @param poolKeeperAddress Pool Keeper's address.
     * @param supplyManagerAddress Supply Manager's address.
     */
    constructor(
        address initialOwner,
        TokenParams[] memory p20,
        TokenParams[] memory p4626,
        address poolKeeperAddress,
        address supplyManagerAddress,
        address[] memory whiteList
    )
        Ownable(initialOwner)
        checkNotZero(initialOwner)
        checkNotZero(poolKeeperAddress)
        checkNotZero(supplyManagerAddress)
    {
        for (uint256 i = 0; i < p20.length; i++) {
            _addToken20(p20[i].pool, p20[i].n);
        }
        for (uint256 i = 0; i < p4626.length; i++) {
            _addToken4626(p4626[i].pool, p4626[i].n);
        }
        poolKeeper = poolKeeperAddress;
        SUPPLY_MANAGER = supplyManagerAddress;

        for (uint256 i = 0; i < whiteList.length; i++) {
            if (whiteList[i] == address(0)) {
                revert EZeroAddress();
            }
            isInWhiteList[whiteList[i]] = true;
        }
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
        uint256 length = pools20.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 balance = IERC20(pools20[i].pool).balanceOf(address(this));
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
            uint256 balance = IERC4626(pools4626[i].pool).balanceOf(address(this));
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
     * @dev Redeem tokens.
     * @param requestIds Request IDs.
     */
    function redeem(uint256[] memory requestIds) external payable {
        _redeem(requestIds);
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
        // Ensure the token is not duplicated.
        if (pools20Map[token].exist || pools4626Map[token].exist) {
            revert EDuplicatedToken();
        }

        // Add the token to the pools.
        pools.push(TokenParams(token, n));
        poolsMap[token] = TokenInfo(true, n, uint32(pools.length - 1));
    }

    /**
     * @dev Delete the last value from the pools.
     * @param token Token address.
     * @param pools List of tokens.
     * @param poolsMap Mapping of tokens.
     */
    function _removeToken(
        address token,
        TokenParams[] storage pools,
        mapping(address => TokenInfo) storage poolsMap
    ) internal {
        if (!poolsMap[token].exist) {
            revert ETokenNotExist();
        }

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            revert ENotZeroBalanceOfRemovedToken();
        }

        uint32 i = poolsMap[token].arrayIndex;
        TokenParams storage lastElement = pools[pools.length - 1];
        pools[i] = lastElement;
        poolsMap[lastElement.pool].arrayIndex = i;
        delete poolsMap[token];
        pools.pop();
    }

    /**
     * @dev Check if the token is an ERC-20 token.
     * @param token Token address.
     * @return result True if the token implements ERC-20.
     */
    function _isERC20(address token) internal view returns (bool) {
        // Ensure the address is a contract before making a call
        if (token.code.length == 0) {
            return false; // Not a contract
        }

        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)) // Test with current contract address
        );

        return success && data.length == 32; // Must return a uint256 value
    }

    /**
     * @dev Check if the token is ERC-4626 token.
     * @param token Token address.
     * @return result True if the token is ERC4626.
     */
    function _isERC4626(address token) internal view returns (bool) {
        // Ensure the address is a contract before making a call
        if (token.code.length == 0) {
            return false; // Not a contract
        }

        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC4626.convertToAssets.selector, uint256(1)) // Test with dummy value (1 share)
        );

        return success && data.length == 32; // Must return a uint256 value
    }

    /**
     * @dev Add the value to the `pools20`.
     * @param token ERC20 token address.
     * @param n Decimal normalization.
     */
    function _addToken20(address token, int8 n) internal {
        // Ensure the token is ERC20 but not ERC4626.
        if (!_isERC20(token) || _isERC4626(token)) {
            revert ENotERC20PoolToken();
        }

        // Add the token to the pools.
        _addToken(token, n, pools20, pools20Map);
    }

    /**
     * @dev Add the value to the pools.
     * @param token ERC20 token address.
     * @param n Decimal normalization.
     */
    function addPool20(address token, int8 n) external onlyOwner {
        _addToken20(token, n);
    }

    /**
     * @dev Delete the last value from the pools.
     * @param token Token address.
     */
    function removePool20(address token) external onlyOwner {
        _removeToken(token, pools20, pools20Map);
    }

    /**
     * @dev Add the value to the pools.
     * @param token ERC4626 token address.
     * @param n Decimal normalization.
     */
    function _addToken4626(address token, int8 n) internal {
        // Ensure the token is ERC20 and also ERC4626.
        if (!_isERC20(token) || !_isERC4626(token)) {
            revert ENotERC4626PoolToken();
        }

        // Add the token to the pools.
        _addToken(token, n, pools4626, pools4626Map);
    }

    /**
     * @dev Add the value to the pools.
     * @param token ERC4626 token address.
     * @param n Decimal normalization.
     */
    function addPool4626(address token, int8 n) external onlyOwner {
        _addToken4626(token, n);
    }

    /**
     * @dev Delete the last value from the pools.
     * @param token Token address.
     */
    function removePool4626(address token) external onlyOwner {
        _removeToken(token, pools4626, pools4626Map);
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
            revert ETokenNotExist();
        }
        // Transfer assets to the token holder.
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(token).safeTransferFrom(from, address(this), value);
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
            revert ETokenNotExist();
        }
    }

    /**
     * @dev Redeem tokens.
     * @param requestIds Request IDs.
     */
    function _redeem(uint256[] memory requestIds) internal virtual {
        if (requestIds.length == 0) {
            revert EEmptyArray();
        }
        // Call the Supply Manager's `redeem` method.
        // Receive the corresponding ERC20 token and total value redeemed.
        // slither-disable-next-line reentrancy-benign
        (address token, uint256 value) = ISupplyManager(SUPPLY_MANAGER).redeem{value: msg.value}(
            address(this),
            requestIds
        );

        // Check if the token is in the `pools20Map` or `pools4626Map`.
        if (pools20Map[token].exist) {
            // Normalize the ERC20 token decimals to 18 mUSD decimals.
            // Reduce the value to redeem for correct `totalSupply` calculation.
            valueToRedeem -= _normalize(pools20Map[token].n, value);
        } else if (pools4626Map[token].exist) {
            // Normalize the ERC20 token decimals to 18 mUSD decimals.
            // Reduce the value to redeem for correct `totalSupply` calculation.
            // Ensure to convert the shares to assets.
            uint256 shares = _normalize(pools4626Map[token].n, value);
            valueToRedeem -= IERC4626(token).convertToAssets(shares);
        } else {
            revert ENotERC20PoolToken();
        }
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
     * @dev Add the target in the white list.
     * @param target Address.
     */
    function addInWhiteList(address target) external onlyOwner checkNotZero(target) {
        if (isInWhiteList[target]) {
            revert EAlreadyAddedInWhiteList();
        }
        isInWhiteList[target] = true;
        emit AddedInWhiteList(target);
    }

    /**
     * @dev Delete the target from the white list.
     * @param target Address.
     */
    function deleteFromWhiteList(address target) external onlyOwner checkNotZero(target) {
        if (!isInWhiteList[target]) {
            revert EAlreadyDeletedInWhiteList();
        }
        delete isInWhiteList[target];
        emit DeletedFromWhiteList(target);
    }

    /**
     * @dev Execute transactions on behalf of the whitelisted contract.
     * Allows `approve` calls to tokens in `pools20Map` and `pools4626Map` without whitelisting.
     * @param target Address.
     * @param data Encoded function data.
     * @return result Result of the function call.
     */
    function execute(
        address target,
        bytes memory data
    ) external payable onlyPoolKeeper returns (bytes memory result) {
        // Decode function selector.
        bytes4 selector;
        // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
        assembly {
            selector := mload(add(data, 32)) // skip: 32 bytes data.length
        }

        // Allow approval calls for any ERC-20 token, but only to whitelisted spender contracts.
        if (selector == IERC20.approve.selector) {
            // Ensure that the value is zero.
            if (msg.value != 0) {
                revert EMsgValueIsNotZero();
            }

            // Decode `approve(spender, amount)` to get the spender address.
            address spender;
            // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
            assembly {
                spender := mload(add(data, 36)) // skip: 32 bytes data.length + 4 bytes selector
            }

            // Ensure spender is whitelisted.
            if (!isInWhiteList[spender]) {
                revert ENotInWhiteList();
            }

            // Execute the function call.
            return target.functionCall(data);
        }

        // Otherwise, check the whitelist.
        if (!isInWhiteList[target]) {
            revert ENotInWhiteList();
        }

        // Execute the function call.
        return target.functionCallWithValue(data, msg.value);
    }

    /**
     * @dev Authorizes a new Agent.
     * @param agent Agent's address.
     * @param auth Boolean flag indicating whether the Agent is authorized.
     */
    function _setAgent(address agent, bool auth) internal {
        IERC20 token = IERC20(IAgent(agent).getERC20Token());
        if (auth) {
            token.forceApprove(agent, type(uint256).max);
        } else {
            token.forceApprove(agent, 0);
        }
    }

    /// @inheritdoc IMoleculaPool
    function setAgent(address agent, bool auth) external onlySupplyManager {
        _setAgent(agent, auth);
    }

    /// @dev Transfer all balance of `fromAddress` to this contract.
    /// @param token Token.
    /// @param fromAddress Address that funds are taken from
    function _transferAllBalance(IERC20 token, address fromAddress) internal {
        uint256 balance = token.balanceOf(fromAddress);
        if (balance > 0) {
            // slither-disable-next-line arbitrary-send-erc20
            token.safeTransferFrom(fromAddress, address(this), balance);
        }
    }

    /// @inheritdoc IMoleculaPool
    function migrate(address oldMoleculaPool) external onlySupplyManager {
        MoleculaPoolTreasury oldMolPool = MoleculaPoolTreasury(payable(oldMoleculaPool));

        // Update `valueToRedeem`.
        valueToRedeem = oldMolPool.valueToRedeem();

        address oldPoolKeeper = oldMolPool.poolKeeper();

        // Check `pools20`.
        {
            TokenParams[] memory pool20 = oldMolPool.getPools20();
            for (uint256 i = 0; i < pool20.length; ++i) {
                TokenParams memory tokenParams = pool20[i];
                if (!pools20Map[tokenParams.pool].exist) {
                    _addToken20(tokenParams.pool, tokenParams.n);
                }
                _transferAllBalance(IERC20(tokenParams.pool), oldPoolKeeper);
            }
        }

        // Check `pools4626`.
        {
            TokenParams[] memory pool4626 = oldMolPool.getPools4626();
            for (uint256 i = 0; i < pool4626.length; ++i) {
                TokenParams memory tokenParams = pool4626[i];
                if (!pools4626Map[tokenParams.pool].exist) {
                    _addToken4626(tokenParams.pool, tokenParams.n);
                }
                _transferAllBalance(IERC20(tokenParams.pool), oldPoolKeeper);
            }
        }

        // Set Agents.
        {
            address[] memory agents = ISupplyManager(SUPPLY_MANAGER).getAgents();
            for (uint256 i = 0; i < agents.length; ++i) {
                _setAgent(agents[i], true);
            }
        }
    }
}
