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
 * @param token Token address.
 * @param n Normalization to 18 decimals: equal to the `18 - poolToken.decimals` value.
 */
struct TokenAndN {
    address token;
    int8 n;
}

/**
 * @dev Token parameters.
 * @param token Token address.
 * @param n Normalization to 18 decimals: equal to the `18 - poolToken.decimals` value.
 * @param isERC4626 Boolean indicating whether the token is of the ERC-4626 type.
 */
struct TokenParams {
    address token;
    int8 n;
    bool isERC4626;
}

enum TokenType {
    None,
    ERC20, // The value represents the ERC20 token type, not an extension.
    ERC4626
}

/**
 * @dev Token information.
 * @param exist Existence of the pool.
 * @param n Normalization to 18 decimals: equal to the `18 - poolToken.decimals` value.
 * @param arrayIndex Index in `TokenParams[] pool`.
 * @param valueToRedeem Value to redeem in the token amount.
 */
struct TokenInfo {
    TokenType tokenType;
    int8 n;
    uint32 arrayIndex;
    uint256 valueToRedeem;
}

/// @notice MoleculaPoolTreasury
contract MoleculaPoolTreasury is Ownable, IMoleculaPool, ZeroValueChecker {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @dev Pool Keeper address.
    address public poolKeeper;

    /// @dev Pool of all the supported tokens including the ones of the ERC20 and ERC4626 types.
    TokenParams[] public pool;

    /// @dev Mapping of the ERC20 pool.
    mapping(address => TokenInfo) public poolMap;

    /// @dev Supply Manager's address.
    address public immutable SUPPLY_MANAGER;

    /// @dev USDT token address.
    address public immutable USDT_ADDRESS;

    /// @dev White list of addresses callable by this contract.
    mapping(address => bool) public isInWhiteList;

    /// @dev Error: Not ERC20 token pool.
    error ENotERC20PoolToken();

    /// @dev Error: Provided array is empty.
    error EEmptyArray();

    /// @dev Error: Duplicated token.
    error EDuplicatedToken();

    /// @dev Error: Removed token does not have the zero balance.
    error ENotZeroBalanceOfRemovedToken();

    /// @dev Error: Removed token does not have the zero `valueToRedeem`.
    error ENotZeroValueToRedeemOfRemovedToken();

    /// @dev Error: Molecula Pool does not have the token.
    error ETokenNotExist();

    /// @dev Emitted when the Molecula Pool is called by a non-PoolKeeper.
    error ENotMyPoolKeeper();

    /// @dev No USDT in `pools20`.
    error ENoUSDT();

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

    /**
     * @dev Initializes the contract setting the initializer address.
     * @param initialOwner Owner's address.
     * @param tokens List of ERC20/ERC4626 tokens.
     * @param poolKeeperAddress Pool Keeper's address.
     * @param supplyManagerAddress Supply Manager's address.
     * @param whiteList List of whitelisted addresses.
     * @param usdtAddress USDT token address required for migration.
     */
    constructor(
        address initialOwner,
        TokenAndN[] memory tokens,
        address poolKeeperAddress,
        address supplyManagerAddress,
        address[] memory whiteList,
        address usdtAddress
    )
        Ownable(initialOwner)
        checkNotZero(initialOwner)
        checkNotZero(poolKeeperAddress)
        checkNotZero(supplyManagerAddress)
    {
        for (uint256 i = 0; i < tokens.length; ++i) {
            TokenAndN memory tokenAndN = tokens[i];
            _addToken(tokenAndN.token, tokenAndN.n);
        }
        poolKeeper = poolKeeperAddress;
        SUPPLY_MANAGER = supplyManagerAddress;

        for (uint256 i = 0; i < whiteList.length; ++i) {
            _addInWhiteList(whiteList[i]);
        }
        USDT_ADDRESS = usdtAddress;
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

    /// @dev Convert the token value (sUSDe, USDe, etc) to mUSDe.
    /// @param value Token value.
    /// @param token Token address.
    /// @param n Normalization to 18 decimals: equal to the `18 - poolToken.decimals` value.
    /// @param isERC4626 Boolean indicating whether the token is of the ERC-4626 type.
    /// @return mUSDAmount mUSD amount.
    function _tokenAmountTomUSD(
        uint256 value,
        address token,
        int8 n,
        bool isERC4626
    ) private view returns (uint256 mUSDAmount) {
        mUSDAmount = 0;
        if (value > 0) {
            if (isERC4626) {
                // Convert `value` (e.g. mUSDe to USDe) to assets.
                value = IERC4626(token).convertToAssets(value);
            }
            // Note: `value` is in USD (e.g. USDT, USDe, etc).
            mUSDAmount = _normalize(n, value);
        }
    }

    /**
     * @dev Returns the total supply of the pool (TVL).
     * @return supply Total pool supply.
     * @return totalRedeem Total redeem value.
     */
    function totalPoolsSupplyAndRedeem() public view returns (uint256 supply, uint256 totalRedeem) {
        supply = 0;
        totalRedeem = 0;
        uint256 len = pool.length;
        for (uint256 i = 0; i < len; ++i) {
            TokenParams memory tokenParam = pool[i];
            address token = tokenParam.token;

            uint256 balance = IERC20(token).balanceOf(address(this));
            supply += _tokenAmountTomUSD(balance, token, tokenParam.n, tokenParam.isERC4626);

            uint256 redeemValue = poolMap[token].valueToRedeem;
            totalRedeem += _tokenAmountTomUSD(
                redeemValue,
                token,
                tokenParam.n,
                tokenParam.isERC4626
            );
        }
    }

    /**
     * @inheritdoc IMoleculaPool
     */
    function totalSupply() public view returns (uint256 res) {
        (uint256 supply, uint256 redeemValue) = totalPoolsSupplyAndRedeem();
        if (redeemValue > supply) {
            return 0;
        }
        return supply - redeemValue;
    }

    /**
     * @dev Add the token to the pool.
     * @param token ERC20 token address.
     * @param n Decimal normalization.
     */
    function _addToken(address token, int8 n) internal {
        // Ensure that the token has the `balanceOf()` function.
        if (!_hasBalanceOf(token)) {
            revert ENotERC20PoolToken();
        }

        bool isERC4626 = _hasConvertToAssets(token);

        // Ensure that the token is not duplicated.
        if (poolMap[token].tokenType != TokenType.None) {
            revert EDuplicatedToken();
        }

        // Add the token to the pool.
        pool.push(TokenParams(token, n, isERC4626));
        poolMap[token] = TokenInfo({
            tokenType: isERC4626 ? TokenType.ERC4626 : TokenType.ERC20,
            n: n,
            arrayIndex: uint32(pool.length - 1),
            valueToRedeem: 0
        });
    }

    /**
     * @dev Delete the last value from the pool.
     * @param token Token address.
     */
    function _removeToken(address token) internal {
        if (poolMap[token].tokenType == TokenType.None) {
            revert ETokenNotExist();
        }

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            revert ENotZeroBalanceOfRemovedToken();
        }
        if (poolMap[token].valueToRedeem > 0) {
            revert ENotZeroValueToRedeemOfRemovedToken();
        }

        uint32 i = poolMap[token].arrayIndex;
        TokenParams storage lastElement = pool[pool.length - 1];
        pool[i] = lastElement;
        poolMap[lastElement.token].arrayIndex = i;
        delete poolMap[token];
        pool.pop();
    }

    /**
     * @dev Check if the token has `balanceOf` function.
     * @param token Token address.
     * @return has True if the token has `balanceOf` function.
     */
    function _hasBalanceOf(address token) internal view returns (bool has) {
        // Ensure that the address is a contract before making a call.
        if (token.code.length == 0) {
            return false; // Not a contract
        }

        // slither-disable-next-line low-level-calls
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)) // Test with current contract address
        );

        return success && data.length == 32; // Must return a uint256 value
    }

    /**
     * @dev Check whether the token has the `convertToAssets` function.
     * @param token Token address.
     * @return has Boolean indicating whether the token has the `convertToAssets` function.
     */
    function _hasConvertToAssets(address token) internal view returns (bool has) {
        // Ensure that the address is a contract before making a call
        if (token.code.length == 0) {
            return false; // Not a contract
        }

        // slither-disable-next-line low-level-calls
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC4626.convertToAssets.selector, uint256(1)) // Test with dummy value (1 share)
        );

        return success && data.length == 32; // Must return a uint256 value
    }

    /**
     * @dev Add the token to the pool.
     * @param token ERC20 token address.
     * @param n Decimal normalization.
     */
    function addToken(address token, int8 n) external onlyOwner {
        _addToken(token, n);
    }

    /**
     * @dev Delete the last value from the pool.
     * @param token Token address.
     */
    function removeToken(address token) external onlyOwner {
        _removeToken(token);
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
        if (poolMap[token].tokenType == TokenType.None) {
            revert ETokenNotExist();
        }
        if (poolMap[token].tokenType == TokenType.ERC20) {
            formattedValue = _normalize(poolMap[token].n, value);
        } else {
            uint256 assets = IERC4626(token).convertToAssets(value);
            formattedValue = _normalize(poolMap[token].n, assets);
        }
        // Transfer assets to the token holder.
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(token).safeTransferFrom(from, address(this), value);
        return formattedValue;
    }

    /// @inheritdoc IMoleculaPool
    function requestRedeem(
        address token,
        uint256 value // In mUSD.
    ) external onlySupplyManager returns (uint256 tokenValue) {
        if (poolMap[token].tokenType == TokenType.None) {
            revert ETokenNotExist();
        }

        if (poolMap[token].tokenType == TokenType.ERC20) {
            // Convert the provided mUSD token value to the given token value (e.g. USDT).
            tokenValue = _normalize(-poolMap[token].n, value);
            // Must reduce the pool amount to correctly calculate `totalSupply` upon redemption.
            poolMap[token].valueToRedeem += tokenValue;
        } else {
            // Convert the provided mUSD token value to stable USD assets (e.g. USDe).
            uint256 assets = _normalize(-poolMap[token].n, value);
            // Convert stable USD assets (e.g. USDe) to the given token value (e.g. sUSDe).
            tokenValue = IERC4626(token).convertToShares(assets);
            // Must reduce the pool amount to correctly calculate `totalSupply` upon redemption.
            poolMap[token].valueToRedeem += tokenValue;
        }
    }

    /**
     * @dev Redeem tokens.
     * @param requestIds Request IDs.
     */
    function redeem(uint256[] memory requestIds) external payable {
        if (requestIds.length == 0) {
            revert EEmptyArray();
        }
        // Call the Supply Manager's `redeem` method.
        // Receive the corresponding ERC20 token and total value redeemed.
        // Note: `value` is in the token amount (e.g. sUSDe).
        // slither-disable-next-line reentrancy-benign
        (address token, uint256 value) = ISupplyManager(SUPPLY_MANAGER).redeem{value: msg.value}(
            address(this),
            requestIds
        );

        // Check whether the token is in `poolMap`.
        if (poolMap[token].tokenType == TokenType.None) {
            revert ETokenNotExist();
        }

        // Reduce the value to redeem for the correct `totalSupply` calculation.
        poolMap[token].valueToRedeem -= value;
    }

    /**
     * @dev Returns the list of the ERC20 pool.
     * @return result List of the ERC20 pool.
     */
    function getTokenPool() external view returns (TokenParams[] memory result) {
        return pool;
    }

    /**
     * @dev Add the target in the white list.
     * @param target Address.
     */
    function _addInWhiteList(address target) private checkNotZero(target) {
        if (isInWhiteList[target]) {
            revert EAlreadyAddedInWhiteList();
        }
        isInWhiteList[target] = true;
    }

    /**
     * @dev Add the target in the white list.
     * @param target Address.
     */
    function addInWhiteList(address target) external onlyOwner {
        _addInWhiteList(target);
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
     * Allows the `approve` calls to tokens in `poolMap` and `poolMap` without whitelisting.
     * @param target Address.
     * @param data Encoded function data.
     * @return result Result of the function call.
     */
    function execute(
        address target,
        bytes memory data
    ) external payable onlyPoolKeeper returns (bytes memory result) {
        // Decode the function selector.
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

    /// @dev Token parameters from old MoleculaPool.
    /// @param pool Token address.
    /// @param n Normalization to 18 decimals: equal to the `18 - poolToken.decimals` value.
    struct OldTokenParams {
        address pool;
        int8 n;
    }

    /// @inheritdoc IMoleculaPool
    function migrate(address oldMoleculaPool) external onlySupplyManager {
        MoleculaPoolTreasury oldMolPool = MoleculaPoolTreasury(payable(oldMoleculaPool));

        address oldPoolKeeper = oldMolPool.poolKeeper();

        // Check `pools20`.
        {
            bytes memory result = oldMoleculaPool.functionStaticCall(
                abi.encodeWithSignature("getPools20()")
            );
            OldTokenParams[] memory pools20 = abi.decode(result, (OldTokenParams[]));
            for (uint256 i = 0; i < pools20.length; ++i) {
                OldTokenParams memory tokenParams = pools20[i];
                if (poolMap[tokenParams.pool].tokenType == TokenType.None) {
                    _addToken(tokenParams.pool, tokenParams.n);
                }
                _transferAllBalance(IERC20(tokenParams.pool), oldPoolKeeper);
            }
        }

        // Check `pools4626`.
        {
            bytes memory result = oldMoleculaPool.functionStaticCall(
                abi.encodeWithSignature("getPools4626()")
            );
            OldTokenParams[] memory pools4626 = abi.decode(result, (OldTokenParams[]));
            for (uint256 i = 0; i < pools4626.length; ++i) {
                OldTokenParams memory tokenParams = pools4626[i];
                if (poolMap[tokenParams.pool].tokenType == TokenType.None) {
                    _addToken(tokenParams.pool, tokenParams.n);
                }
                _transferAllBalance(IERC20(tokenParams.pool), oldPoolKeeper);
            }
        }

        // Update `valueToRedeem`.
        if (poolMap[USDT_ADDRESS].tokenType == TokenType.None) {
            revert ENoUSDT();
        }
        {
            bytes memory result = oldMoleculaPool.functionStaticCall(
                abi.encodeWithSignature("valueToRedeem()")
            );
            // Get the old `valueToRedeem` in mUSD.
            uint256 oldValueToRedeem = abi.decode(result, (uint256));
            // Convert the value to the token amount in USDT.
            poolMap[USDT_ADDRESS].valueToRedeem = oldValueToRedeem / 10 ** 12;
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
