// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

import {IAgent} from "../../retail/interfaces/IAgent.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISupplyManager} from "../../retail/interfaces/ISupplyManager.sol";
import {WmUsdtToken} from "./WmUsdtToken.sol";
import {IOracle} from "../../common/interfaces/IOracle.sol";

import {LZMessage} from "../../common/LZMessage.sol";
import {OptionsLZ} from "../../common/OptionsLZ.sol";

import {ServerControlled} from "../../common/ServerControlled.sol";

enum DepositStatus {
    None,
    ReadyToConfirm,
    Executed
}

struct DepositInfo {
    DepositStatus status;
    uint256 queryId;
    uint256 shares;
}

/// @notice Agent contract to call LayerZero.
contract AgentLZ is OApp, IAgent, ServerControlled, OptionsLZ, LZMessage {
    using SafeERC20 for IERC20;

    /// @dev LayerZero destination chain ID.
    uint32 public immutable DST_EID;

    /// @dev Mapping of executed deposits.
    mapping(uint256 => DepositInfo) public deposits;

    /// @dev SupplyManager interface.
    address public immutable SUPPLY_MANAGER;

    /// @dev WmUSDT token's address.
    address public immutable WM_USDT;

    /// @dev Boolean flag indicating whether the oracle data is sent via LayerZero.
    bool public updateOracleData;

    /// @dev Error: Operation already exists.
    error EOperationAlreadyExists();

    /// @dev Error: Operation not ready.
    error EOperationNotReady();

    /// @dev Error: Not my Supply Manager.
    error ENotMySupplyManager();

    /**
     * @dev Event emitted when the redeem operation is executed.
     */
    event Redeem();

    /// @dev Modifier that checks whether the caller is the Supply Manager.
    modifier onlySupplyManager() {
        if (msg.sender != SUPPLY_MANAGER) {
            revert ENotMySupplyManager();
        }
        _;
    }

    /**
     * @dev Initializes the contract setting the initializer's address.
     * @param initialOwner Owner's address.
     * @param authorizedLZConfiguratorAddress Authorized LayerZero configurator's address.
     * @param server Authorized Server's address.
     * @param endpoint LayerZero endpoint contract's address.
     * @param supplyManagerAddress Supply Manager's contract address.
     * @param lzDstEid LayerZero destination chain ID.
     * @param wmUSDTAddress WmUSDT token address.
     * @param lzOpt LayerZero's call options.
     */
    constructor(
        address initialOwner,
        address authorizedLZConfiguratorAddress,
        address server,
        address endpoint,
        address supplyManagerAddress,
        uint32 lzDstEid,
        address wmUSDTAddress,
        bytes memory lzOpt
    )
        OApp(endpoint, initialOwner)
        OptionsLZ(initialOwner, authorizedLZConfiguratorAddress, lzOpt)
        ServerControlled(server)
    {
        SUPPLY_MANAGER = supplyManagerAddress;
        DST_EID = lzDstEid;
        WM_USDT = wmUSDTAddress;
        updateOracleData = true;
    }

    /**
     * @dev Called when the data is received from the protocol. It overrides the equivalent function in the parent contract.
     * Protocol messages are defined as packets, comprised of the following parameters. Call on depositing.
     * @param _origin Struct containing information about where the packet came from.
     * @param _guid Global unique identifier for tracking the packet.
     * @param payload Encoded message.
     * @param _executor Executor address as specified by the OApp.
     * @param _options Extra data or options to trigger upon receipt.
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata payload,
        address _executor, // Executor address as specified by the OApp.
        bytes calldata _options // Extra data or options to trigger on receipt.
    ) internal override serverIsDisabled {
        _origin;
        _guid;
        _executor;
        _options;
        // Decode the payload to get the message. Get the message type.
        uint8 msgType = uint8(payload[0]);
        if (msgType == REQUEST_DEPOSIT) {
            // Decode the payload.
            (uint256 requestId, uint256 value) = LZMessage.lzDecodeRequestDepositMessage(
                payload[1:]
            );
            // Call the `deposit` method.
            _deposit(requestId, value);
        } else if (msgType == REQUEST_REDEEM) {
            // Decode the payload.
            (uint256 requestId, uint256 value) = LZMessage.lzDecodeRequestRedeemMessage(
                payload[1:]
            );
            // Call the `requestRedeem` method.
            _requestRedeem(requestId, value);
        } else {
            revert LZMessage.ELzUnknownMessage();
        }
    }

    /**
     * @dev Deposit method called by the server.
     * @param requestId Deposit request ID.
     * @param value Deposit amount.
     */
    function requestDeposit(
        uint256 requestId,
        uint256 value
    ) external serverIsEnabled onlyAuthorizedServer {
        // Call the `deposit` method.
        _deposit(requestId, value);
    }

    /**
     * @dev Deposit method.
     * @param requestId Deposit request ID.
     * @param value Deposit amount.
     */
    function _deposit(uint256 requestId, uint256 value) internal {
        // Check whether the deposit operation already exists.
        if (deposits[requestId].status != DepositStatus.None) {
            revert EOperationAlreadyExists();
        }

        // Call the Supply Manager's deposit method.
        // slither-disable-next-line reentrancy-no-eth
        uint256 shares = ISupplyManager(SUPPLY_MANAGER).deposit(WM_USDT, requestId, value);

        // Mint wmUSDT tokens.
        // slither-disable-next-line reentrancy-no-eth
        WmUsdtToken(WM_USDT).mint(value);

        // Store the deposit operation in the `deposits` mapping.
        deposits[requestId] = DepositInfo(DepositStatus.ReadyToConfirm, requestId, shares);

        // Emit an event to log the deposit operation.
        emit Deposit(requestId, value, shares);
    }

    /**
     * @notice Sends a message from the source to the destination chain.
     * @param requestId Deposit request ID.
     */
    function confirmDeposit(uint256 requestId) external payable {
        // Check if the deposit operation already exists.
        if (deposits[requestId].status != DepositStatus.ReadyToConfirm) {
            revert EOperationNotReady();
        }

        // Send a cross-chain message to the Accountant.
        if (!serverEnabled) {
            bytes memory lzOptions;
            // Encodes the message before invoking `_lzSend`. Must be replaced with the relevant data you want to send.
            bytes memory payload = "";
            if (updateOracleData) {
                // Get the LayerZero options.
                lzOptions = getLzOptions(CONFIRM_DEPOSIT_AND_UPDATE_ORACLE, 0);
                // Get `totalValue` and `totalShares`.
                (uint256 totalValue, uint256 totalShares) = IOracle(SUPPLY_MANAGER)
                    .getTotalSupply();
                // Get the payload for LayerZero.
                payload = LZMessage.lzEncodeConfirmDepositMessageAndUpdateOracle(
                    requestId,
                    deposits[requestId].shares,
                    totalValue,
                    totalShares
                );
            } else {
                // Get the LayerZero options.
                lzOptions = getLzOptions(CONFIRM_DEPOSIT, 0);
                // Get the payload for LayerZero.
                payload = LZMessage.lzEncodeConfirmDepositMessage(
                    requestId,
                    deposits[requestId].shares
                );
            }
            // Use LayerZero.
            _lzSend(
                DST_EID,
                payload,
                lzOptions,
                // Fee in the native gas and ZRO token.
                MessagingFee(msg.value, 0),
                // Refund address in case of a failed source message.
                payable(msg.sender)
            );
        } /* else {
            // Use the Server.

            // Do nothing when using the server.
            // Emit the `DepositConfirm` event bellow.
        } */

        // Set the status to `Executed`.
        deposits[requestId].status = DepositStatus.Executed;

        // Emit an event to log the deposit confirmation operation.
        emit DepositConfirm(requestId, deposits[requestId].shares);
    }

    /**
     * @notice `requestRedeem` for server.
     * @param requestId Redeem operation request ID.
     * @param shares Redeem operation amount.
     */
    function requestRedeem(
        uint256 requestId,
        uint256 shares
    ) external serverIsEnabled onlyAuthorizedServer {
        _requestRedeem(requestId, shares);
    }

    /**
     * @notice Calls the Supply Manager's `requestRedeem` method.
     * @param requestId Redeem operation request ID.
     * @param shares Redeem operation amount.
     */
    function _requestRedeem(uint256 requestId, uint256 shares) internal {
        // Call the Supply Manager's `requestRedeem` method.
        uint256 value = ISupplyManager(SUPPLY_MANAGER).requestRedeem(
            address(WM_USDT),
            requestId,
            shares
        );
        // Emit an event to log the redeem operation.
        emit RedeemRequest(requestId, shares, value);
    }

    /** @dev Quotes the gas needed to pay for the full omnichain transaction.
     * @param msgType Message type.
     * @param arrLen Length of the array for `CONFIRM_REDEEM` and `DISTRIBUTE_YIELD` messages. For other types, pass 0.
     * @return nativeFee Estimated gas fee in the native gas.
     * @return lzTokenFee Estimated gas fee in the ZRO token.
     * @return lzOptions LayerZero options.
     */
    function quote(
        uint8 msgType,
        uint256 arrLen
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee, bytes memory lzOptions) {
        // Check whether the quote is applied for making requests, which require cross-chain transporting.
        if (serverEnabled) {
            // No quote is applied.
            return (0, 0, lzOptions);
        }
        bytes memory payload = "";
        if (msgType == CONFIRM_DEPOSIT || msgType == CONFIRM_DEPOSIT_AND_UPDATE_ORACLE) {
            if (updateOracleData) {
                payload = LZMessage.lzDefaultConfirmDepositMessageAndUpdateOracle();
                lzOptions = getLzOptions(CONFIRM_DEPOSIT_AND_UPDATE_ORACLE, 0);
            } else {
                payload = LZMessage.lzDefaultConfirmDepositMessage();
                lzOptions = getLzOptions(CONFIRM_DEPOSIT, 0);
            }
        } else if (msgType == CONFIRM_REDEEM) {
            payload = LZMessage.lzDefaultConfirmRedeemMessage(arrLen);
            lzOptions = getLzOptions(CONFIRM_REDEEM, arrLen);
        } else if (msgType == DISTRIBUTE_YIELD || msgType == DISTRIBUTE_YIELD_AND_UPDATE_ORACLE) {
            if (updateOracleData) {
                payload = LZMessage.lzDefaultDistributeYieldMessageAndUpdateOracle(arrLen);
                lzOptions = getLzOptions(DISTRIBUTE_YIELD_AND_UPDATE_ORACLE, arrLen);
            } else {
                payload = LZMessage.lzDefaultDistributeYieldMessage(arrLen);
                lzOptions = getLzOptions(DISTRIBUTE_YIELD, arrLen);
            }
        } else if (msgType == UPDATE_ORACLE) {
            payload = LZMessage.lzDefaultUpdateOracleMessage();
            lzOptions = getLzOptions(UPDATE_ORACLE, 0);
        } else {
            revert LZMessage.ELzUnknownMessage();
        }
        MessagingFee memory fee = _quote(DST_EID, payload, lzOptions, false);
        return (fee.nativeFee, fee.lzTokenFee, lzOptions);
    }

    /// @inheritdoc ServerControlled
    function setServerEnable(bool enable) external override onlyOwner {
        serverEnabled = enable;
        // If the server is enabled, `updateOracleData` must be disabled as it requires LayerZero.
        if (serverEnabled) {
            updateOracleData = false;
        }
    }

    /// @inheritdoc ServerControlled
    function setAuthorizedServer(address server) external override onlyOwner {
        authorizedServer = server;
    }

    /**
     * @dev Sets the `updateOracleData` status.
     * @param isSend `updateOracleData` status.
     */
    function setSendOracleData(bool isSend) external onlyOwner {
        updateOracleData = isSend;
        // If we enable `updateOracleData` that requires LayerZero, we should also disable the server.
        if (updateOracleData && serverEnabled) {
            serverEnabled = false;
        }
    }

    /// @inheritdoc IAgent
    function redeem(
        address fromAddress,
        uint256[] memory requestIds,
        uint256[] memory values,
        uint256 totalValue
    ) external payable onlySupplyManager {
        fromAddress;
        // Burn wmUSDT tokens.
        // Note: Burn is not possible while a wmUSDT <-> USDT swap is in progress.
        // As a result, the operation will be internally reverted.
        // Refer to the `burn` function implementation for details.
        WmUsdtToken(WM_USDT).burn(totalValue);

        // Send to LayerZero if there is no server available.
        if (!serverEnabled) {
            // Get options for LayerZero.
            bytes memory lzOptions = getLzOptions(CONFIRM_REDEEM, requestIds.length);

            // Get the payload for LayerZero.
            bytes memory payload = LZMessage.lzEncodeConfirmRedeemMessage(requestIds, values);

            // Use LayerZero.
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

        // Emit an event to log the redeem operation.
        emit Redeem();
    }

    /// @inheritdoc IAgent
    function getERC20Token() external view returns (address token) {
        return WM_USDT;
    }

    /// @inheritdoc IAgent
    function distribute(
        address[] memory users,
        uint256[] memory shares
    ) external payable onlySupplyManager {
        // Send to LayerZero if there is no server available.
        if (!serverEnabled) {
            bytes memory lzOptions;
            bytes memory payload;
            if (updateOracleData) {
                // Get options for LayerZero.
                lzOptions = getLzOptions(DISTRIBUTE_YIELD_AND_UPDATE_ORACLE, users.length);
                // Get `totalValue` and `totalShares`.
                (uint256 oracleTotalValue, uint256 totalShares) = IOracle(SUPPLY_MANAGER)
                    .getTotalSupply();
                // Get the payload for LayerZero.
                payload = LZMessage.lzEncodeDistributeYieldMessageAndUpdateOracle(
                    users,
                    shares,
                    oracleTotalValue,
                    totalShares
                );
            } else {
                // Get options for LayerZero.
                lzOptions = getLzOptions(DISTRIBUTE_YIELD, users.length);
                // Get the payload for LayerZero.
                payload = LZMessage.lzEncodeDistributeYieldMessage(users, shares);
            }
            // Use LayerZero.
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

        // Emit an event to log operation.
        // TODO Decrease the gas cost.
        emit DistributeYield(users, shares);
    }

    /**
     * @dev Updates the Oracle on the TRON network.
     */
    function updateOracle() external payable {
        // Send to LayerZero if there is no server available.
        if (!serverEnabled) {
            // Get `totalValue` and `totalShares`.
            (uint256 totalValue, uint256 totalShares) = IOracle(SUPPLY_MANAGER).getTotalSupply();
            // Get options for LayerZero.
            bytes memory lzOptions = getLzOptions(UPDATE_ORACLE, 0);
            // Get the payload for LayerZero.
            bytes memory payload = LZMessage.lzEncodeUpdateOracle(totalValue, totalShares);
            // Use LayerZero.
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
