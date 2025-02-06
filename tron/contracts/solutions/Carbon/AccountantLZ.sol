// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IAccountant} from "@molecula-monorepo/ethereum/contracts/retail/interfaces/IAccountant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LZMessage} from "@molecula-monorepo/ethereum/contracts/common/LZMessage.sol";
import {OptionsLZ} from "@molecula-monorepo/ethereum/contracts/common/OptionsLZ.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IRebaseToken} from "@molecula-monorepo/ethereum/contracts/retail/interfaces/IRebaseToken.sol";
import {ISetterOracle} from "@molecula-monorepo/ethereum/contracts/common/interfaces/ISetterOracle.sol";
import {ServerControlled} from "@molecula-monorepo/ethereum/contracts/common/ServerControlled.sol";

/// @notice Accountant contract to work with LayerZero.
contract AccountantLZ is OApp, LZMessage, IAccountant, ServerControlled, OptionsLZ {
    using SafeERC20 for IERC20;

    /// @dev Multisignature Finance Vault address.
    address public immutable SAFE_VAULT;

    /// @dev LayerZero destination chain ID.
    uint32 public immutable DST_EID;

    /// @dev Molecula token address.
    address public moleculaToken;

    /// @dev Treasury address.
    address public treasury;

    /// @dev Token address.
    IERC20 public immutable TOKEN;

    /// @dev Oracle contract address.
    ISetterOracle public immutable ORACLE;

    /// @dev Modifier that checks whether the caller is the Molecula token.
    modifier onlyMoleculaToken() {
        if (moleculaToken != msg.sender) {
            revert NotMyToken();
        }
        _;
    }

    /// @dev Error: Operation already exists.
    error EOperationAlreadyExists();

    /// @dev Error: Operation not ready.
    error EOperationNotReady();

    /// @dev Error: Not my token.
    error NotMyToken();

    /**
     * @dev Initializes the contract setting the initializer address.
     * @param initialOwner Owner address.
     * @param authorizedLZConfiguratorAddress Authorized LayerZero configurator address.
     * @param server Authorized Server address.
     * @param endpoint LayerZero endpoint contract address.
     * @param safeVaultAddress Safe Vault contract address.
     * @param lzDstEid LayerZero destination chain ID.
     * @param moleculaTokenAddress Molecula token address.
     * @param treasuryAddress Treasury address.
     * @param tokenAddress Token address.
     * @param lzOpt LayerZero call options.
     * @param oracleAddress Oracle contract address.
     */
    constructor(
        address initialOwner,
        address authorizedLZConfiguratorAddress,
        address server,
        address endpoint,
        address safeVaultAddress,
        uint32 lzDstEid,
        address moleculaTokenAddress,
        address treasuryAddress,
        address tokenAddress,
        bytes memory lzOpt,
        address oracleAddress
    )
        OApp(endpoint, initialOwner)
        OptionsLZ(initialOwner, authorizedLZConfiguratorAddress, lzOpt)
        ServerControlled(server)
    {
        SAFE_VAULT = safeVaultAddress;
        DST_EID = lzDstEid;
        moleculaToken = moleculaTokenAddress;
        treasury = treasuryAddress;
        TOKEN = IERC20(tokenAddress);
        ORACLE = ISetterOracle(oracleAddress);
    }

    /**
     * @dev Confirms a deposit.
     * The function gets called when the data is received from the protocol. It overrides the equivalent function in the parent contract.
     * Protocol messages are defined as packets, comprised of the following parameters.
     * @param _origin Struct containing information about where the packet came from.
     * @param _guid Global unique identifier for tracking the packet.
     * @param payload Encoded message.
     * @param _executor Executor address as specified by the OApp.
     * @param _options Any extra data or options to trigger on receipt.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address _executor, // Executor address as specified by the OApp.
        bytes calldata _options // Any extra data or options to trigger on receipt.
    ) internal override serverIsDisabled {
        _origin;
        _guid;
        _executor;
        _options;
        // Decode the payload to get the message. Get the message type.
        uint8 msgType = uint8(payload[0]);
        // Confirm the deposit message.
        if (msgType == CONFIRM_DEPOSIT) {
            (uint256 requestId, uint256 shares) = lzDecodeConfirmDepositMessage(payload[1:]);
            _confirmDeposit(requestId, shares);
        } else if (msgType == CONFIRM_REDEEM) {
            (uint256[] memory requestId, uint256[] memory values) = lzDecodeConfirmRedeemMessage(
                payload[1:]
            );
            _redeem(requestId, values);
        } else if (msgType == DISTRIBUTE_YIELD) {
            (address[] memory users, uint256[] memory shares) = lzDecodeDistributeYieldMessage(
                payload[1:]
            );
            _distributeYield(users, shares);
        } else if (msgType == CONFIRM_DEPOSIT_AND_UPDATE_ORACLE) {
            (
                uint256 requestId,
                uint256 shares,
                uint256 totalValue,
                uint256 totalShares
            ) = lzDecodeConfirmDepositMessageAndUpdateOracle(payload[1:]);
            _setOracleData(totalValue, totalShares);
            _confirmDeposit(requestId, shares);
        } else if (msgType == DISTRIBUTE_YIELD_AND_UPDATE_ORACLE) {
            (
                address[] memory users,
                uint256[] memory shares,
                uint256 totalValue,
                uint256 totalShares
            ) = lzDecodeDistributeYieldMessageAndUpdateOracle(payload[1:]);
            _setOracleData(totalValue, totalShares);
            _distributeYield(users, shares);
        } else if (msgType == UPDATE_ORACLE) {
            (uint256 totalValue, uint256 totalShares) = lzDecodeUpdateOracle(payload[1:]);
            _setOracleData(totalValue, totalShares);
        } else {
            revert ELzUnknownMessage();
        }
    }

    /**
     * @dev Sets the oracle data.
     * @param totalValue Total value.
     * @param totalShares Total shares.
     */
    function _setOracleData(uint256 totalValue, uint256 totalShares) internal {
        ORACLE.setTotalSupply(totalValue, totalShares);
    }

    /**
     * @dev Distributes the yield called by the server.
     * @param users User's addresses.
     * @param shares Shares to distribute.
     */
    function distributeYield(
        address[] memory users,
        uint256[] memory shares
    ) external serverIsEnabled onlyAuthorizedServer {
        _distributeYield(users, shares);
    }

    /**
     * @dev  Distributes yield.
     * @param users User's addresses.
     * @param shares Shares to distribute.
     */
    function _distributeYield(address[] memory users, uint256[] memory shares) internal {
        for (uint256 i = 0; i < users.length; i++) {
            IRebaseToken(moleculaToken).distribute(users[i], shares[i]);
        }
    }

    /**
     * @dev Confirms a deposit called by the server.
     * @param requestId Deposit request ID.
     * @param shares Amount to deposit.
     */
    function confirmDeposit(
        uint256 requestId,
        uint256 shares
    ) external serverIsEnabled onlyAuthorizedServer {
        _confirmDeposit(requestId, shares);
    }

    /**
     * @dev Confirms a deposit.
     * @param requestId Deposit request ID.
     * @param shares Amount to deposit.
     */
    function _confirmDeposit(uint256 requestId, uint256 shares) internal {
        IRebaseToken(moleculaToken).confirmDeposit(requestId, shares);
    }

    /**
     * @dev Redeem operation called by the server.
     * @param requestIds Deposit request IDs.
     * @param values Values to deposit.
     */
    function redeem(
        uint256[] memory requestIds,
        uint256[] memory values
    ) external serverIsEnabled onlyAuthorizedServer {
        _redeem(requestIds, values);
    }

    /**
     * @dev Redeems the funds.
     * @param requestIds Deposit request IDs.
     * @param values Amount to deposit.
     */
    function _redeem(uint256[] memory requestIds, uint256[] memory values) internal {
        uint256 totalValue = IRebaseToken(moleculaToken).redeem(requestIds, values);
        ITreasury(treasury).redeem(totalValue);
    }

    /**
     * @dev Confirms a redemption.
     * @param user User's address.
     * @param value Amount to confirm.
     */
    function confirmRedeem(address user, uint256 value) external onlyMoleculaToken {
        ITreasury(treasury).confirmRedeem(user, value);
    }

    /**
     * @notice Sends a message from the source to destination chain.
     * @param requestId Deposit request ID.
     * @param user User address.
     * @param value Deposit amount.
     */
    function requestDeposit(
        uint256 requestId,
        address user,
        uint256 value
    ) external payable onlyMoleculaToken {
        if (value > 0) {
            // Transfer ERC20 tokens from user to the Treasury.
            // slither-disable-next-line arbitrary-send-erc20
            TOKEN.safeTransferFrom(user, treasury, value);
            if (!serverEnabled) {
                // Get options for LayerZero.
                bytes memory lzOptions = getLzOptions(REQUEST_DEPOSIT, 0);
                // Encodes the message before invoking `_lzSend`.
                bytes memory payload = lzEncodeRequestDepositMessage(requestId, value);
                // Send data to LayerZero.
                _lzSend(
                    DST_EID,
                    payload,
                    lzOptions,
                    // Fee in the native gas and ZRO token.
                    MessagingFee(msg.value, 0),
                    // Refund address in case of a failed source message.
                    payable(msg.sender)
                );
            }
        }
    }

    /// @inheritdoc IAccountant
    function requestRedeem(uint256 requestId, uint256 shares) external payable onlyMoleculaToken {
        if (!serverEnabled) {
            // Get options for LayerZero.
            bytes memory lzOptions = getLzOptions(REQUEST_REDEEM, 0);
            // Encodes the message before invoking `_lzSend`.
            bytes memory payload = lzEncodeRequestRedeemMessage(requestId, shares);
            // Send data to LayerZero.
            _lzSend(
                DST_EID,
                payload,
                lzOptions,
                // Fee in the native gas and ZRO token.
                MessagingFee(msg.value, 0),
                // Refund address in case of a failed source message.
                payable(msg.sender)
            );
        }
    }

    /** @dev Quotes the gas needed to pay for the full omnichain transaction.
     * @param msgType Message type.
     * @return nativeFee Estimated gas fee in the native gas.
     * @return lzTokenFee Estimated gas fee in the ZRO token.
     * @return lzOptions LayerZero options.
     */
    function quote(
        uint8 msgType
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee, bytes memory lzOptions) {
        // Check whether the quote is applied for making requests, which require cross-chain transporting.
        if (serverEnabled) {
            // No quote is applied.
            return (0, 0, lzOptions);
        }
        bytes memory payload = "";
        // Get the message type
        if (msgType == REQUEST_DEPOSIT) {
            lzOptions = getLzOptions(REQUEST_DEPOSIT, 0);
            payload = lzDefaultRequestDepositMessage();
        } else if (msgType == REQUEST_REDEEM) {
            lzOptions = getLzOptions(REQUEST_REDEEM, 0);
            payload = lzDefaultRequestRedeemMessage();
        } else {
            revert ELzUnknownMessage();
        }
        MessagingFee memory fee = _quote(DST_EID, payload, lzOptions, false);
        return (fee.nativeFee, fee.lzTokenFee, lzOptions);
    }

    /**
     * @dev Transfers tokens to the Bridge Vault.
     * @param erc20Token Token contract address.
     * @param value Amount to transfer.
     */
    // slither-disable-next-line erc20-interface
    function transfer(address erc20Token, uint256 value) external onlyOwner {
        // Attempt to transfer the tokens. Revert the transaction if the transfer fails.
        IERC20(erc20Token).safeTransfer(SAFE_VAULT, value);
    }

    /**
     * @dev Sets the Molecula token address.
     * @param moleculaTokenAddress Molecula token address.
     */
    function setMoleculaToken(address moleculaTokenAddress) external onlyOwner {
        moleculaToken = moleculaTokenAddress;
    }

    /// @inheritdoc ServerControlled
    function setServerEnable(bool enable) external override onlyOwner {
        serverEnabled = enable;
    }

    /// @inheritdoc ServerControlled
    function setAuthorizedServer(address server) external override onlyOwner {
        authorizedServer = server;
    }

    /**
     * @dev Sets the Treasure address.
     * @param treasureAddress Treasure address.
     */
    function setTreasury(address treasureAddress) external onlyOwner {
        treasury = treasureAddress;
    }
}
