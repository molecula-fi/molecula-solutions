// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {ISwftSwap} from "@molecula-monorepo/ethereum/contracts/common/interfaces/ISwftSwap.sol";
import {ServerControlled} from "@molecula-monorepo/ethereum/contracts/common/ServerControlled.sol";
import {OptionsLZ} from "@molecula-monorepo/ethereum/contracts/common/OptionsLZ.sol";
import {LZMsgTypes} from "@molecula-monorepo/ethereum/contracts/common/LZMsgTypes.sol";

/// @notice Treasury contract to work with mUSD.
contract Treasury is OApp, ITreasury, ServerControlled, LZMsgTypes, OptionsLZ {
    using SafeERC20 for IERC20;

    /// @dev Multisignature Finance Vault address.
    address public immutable SAFE_VAULT;

    /// @dev Token address.
    IERC20 public immutable USDT_TOKEN;

    /// @dev Accountant address.
    address public accountant;

    /// @dev Amount of locked tokens to redeem.
    uint256 public lockedToRedeem;

    /// @dev LayerZero destination chain ID.
    uint32 public immutable DST_EID;

    /// @dev SWFT Bridge contract address.
    address public immutable SWFT_BRIDGE;

    /// @dev Swap destination address.
    string public swftDestination;

    /// @dev Swap operation value.
    uint256 public swapValue;

    /// @dev Event: Swap request.
    /// @param value Number of tokens to swap.
    event SwapRequest(uint256 value);

    /// @dev Event: SWFT swap.
    /// @param value Number of tokens to swap.
    /// @param minReturnAmount Minimum return amount.
    event Swap(uint256 value, uint256 minReturnAmount);

    /// @dev Error: Only Accountant.
    error EOnlyAccountant();

    /// @dev Error: Unexpected insufficiency of funds.
    error EUnexpectedLackOfFunds();

    /// @dev Error: No active operation.
    error ENoActiveOperation();

    /// @dev Error: Operation is active.
    error EOperationIsActive();

    /// @dev Modifier: Only Accountant.
    modifier onlyAccountant() {
        if (address(accountant) != msg.sender) {
            revert EOnlyAccountant();
        }
        _;
    }

    /**
     * @dev Initializes the contract setting the initializer address.
     * @param initialOwner Owner address.
     * @param server Authorized Server address.
     * @param endpoint LayerZero endpoint contract address.
     * @param safeVaultAddress Safe Vault contract address.
     * @param accountantAddress Accountant contract address.
     * @param tokenAddress Token address.
     * @param lzBaseOpt LayerZero call options.
     * @param authorizedLZConfiguratorAddress Authorized LayerZero configurator address.
     * @param lzDstEid LayerZero destination chain ID.
     * @param swftBridgeAddress SWFT Bridge contract address.
     * @param swftDest SWFT swap destination address.
     */
    constructor(
        address initialOwner,
        address server,
        address endpoint,
        address safeVaultAddress,
        address accountantAddress,
        address tokenAddress,
        bytes memory lzBaseOpt,
        address authorizedLZConfiguratorAddress,
        uint32 lzDstEid,
        address swftBridgeAddress,
        string memory swftDest
    )
        OApp(endpoint, initialOwner)
        ServerControlled(server)
        OptionsLZ(initialOwner, authorizedLZConfiguratorAddress, lzBaseOpt)
    {
        SAFE_VAULT = safeVaultAddress;
        USDT_TOKEN = IERC20(tokenAddress);
        accountant = accountantAddress;
        DST_EID = lzDstEid;
        SWFT_BRIDGE = swftBridgeAddress;
        swftDestination = swftDest;
    }

    /**
     * @dev Transfers tokens to the Safe Vault.
     * @param erc20Token Token contract address.
     * @param value Amount to transfer.
     */
    // slither-disable-next-line erc20-interface
    function transfer(address erc20Token, uint256 value) external onlyOwner {
        // Attempt to transfer the tokens. Revert the transaction if the transfer fails.
        IERC20(erc20Token).safeTransfer(SAFE_VAULT, value);
    }

    /**
     * @dev Sets the Accountant address.
     * @param newAccountant New Accountant address.
     */
    function setAccountant(address newAccountant) external onlyOwner {
        accountant = newAccountant;
    }

    /// @inheritdoc ITreasury
    function redeem(uint256 totalValue) external onlyAccountant {
        // Get the USDT balance.
        uint256 balance = USDT_TOKEN.balanceOf(address(this));

        // Ensure the "new" locked value is not greater than the balance.
        if (balance < lockedToRedeem + totalValue) {
            revert EUnexpectedLackOfFunds();
        }

        // Change the locked value to redeem.
        lockedToRedeem += totalValue;
    }

    /// @inheritdoc ITreasury
    function confirmRedeem(address user, uint256 value) external onlyAccountant {
        // Get the USDT balance.
        uint256 balance = USDT_TOKEN.balanceOf(address(this));

        // Ensure the value is not greater than the balance.
        if (balance < value) {
            revert EUnexpectedLackOfFunds();
        }

        // Ensure the "new" locked value is non-negative.
        if (lockedToRedeem < value) {
            revert EUnexpectedLackOfFunds();
        }

        // Change the locked value to redeem.
        lockedToRedeem -= value;

        // Transfer the "unlocked" redeemed value to the user.
        USDT_TOKEN.safeTransfer(user, value);
    }

    /**
     * @dev Encodes the message.
     * @param value Number of tokens to swap.
     * @return message Encoded message.
     */
    function _encodeMessage(uint256 value) internal pure returns (bytes memory message) {
        message = abi.encodePacked(value);
    }

    /**
     * @dev Decodes the message.
     * @param message Encoded message.
     * @return value Decoded value.
     */
    function _decodeMessage(bytes memory message) internal pure returns (uint256 value) {
        value = abi.decode(message, (uint256));
    }

    /**
     * @dev Gets called when the data is received from the protocol. It overrides the equivalent function in the parent contract.
     * Protocol messages are defined as packets, comprised of the following parameters. Call on deposit.
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

        _requestToSwapWmUSDT(_decodeMessage(payload));
    }

    /**
     * @dev Request the wmUSDT -> USDT swap operation.
     * @param value Number of tokens to swap.
     */
    function requestToSwapWmUSDT(uint256 value) external onlyAuthorizedServer {
        _requestToSwapWmUSDT(value);
    }

    /**
     * @dev Request the wmUSDT -> USDT swap operation.
     * @param value Number of tokens to swap.
     */
    function _requestToSwapWmUSDT(uint256 value) internal {
        // Check whether there is an active swap.
        if (swapValue != 0) {
            revert EOperationIsActive();
        }
        // Save the swap value.
        swapValue = value;
        // Emit the event.
        emit SwapRequest(swapValue);
    }

    /**
     * @dev Confirms the swap and transfers tokens to the SWFT Bridge.
     * @param minReturnAmount Minimum return value.
     */
    function swapWmUsdt(uint256 minReturnAmount) external onlyAuthorizedServer {
        // Check whether there is an active swap.
        if (swapValue == 0) {
            revert ENoActiveOperation();
        }
        // Transfer tokens to the SWFT Bridge.
        // slither-disable-next-line reentrancy-no-eth
        _transferToSwftBridge(swapValue, minReturnAmount);

        // Finish the swap operation.
        swapValue = 0;
    }

    /**
     * @dev Transfers tokens to the SWFT Bridge.
     * @param value USDT amount to transfer.
     * @param minReturnValue Minimum return value.
     */
    function _transferToSwftBridge(uint256 value, uint256 minReturnValue) internal {
        // Approve to the bridge.
        USDT_TOKEN.forceApprove(SWFT_BRIDGE, value);
        // Call the bridge.
        ISwftSwap(SWFT_BRIDGE).swap(
            address(USDT_TOKEN),
            "USDT(ERC20)", // https://github.com/SwftCoins/GPT4-Plugin/blob/274765ca07c7e055186b37dcef9da50cf32c6d14/token_files/coin_list.json#L147
            swftDestination,
            value,
            minReturnValue
        );

        // Emit the event.
        emit Swap(value, minReturnValue);
    }

    /**
     * @dev Confirms the swap and sends the total supply to LayerZero.
     */
    function confirmSwapUsdt() external payable onlyAuthorizedServer {
        // Get USDT balance reduced by the locked value.
        uint256 balance = USDT_TOKEN.balanceOf(address(this)) - lockedToRedeem;

        if (!serverEnabled) {
            // Get options for LayerZero.
            bytes memory lzOptions = getLzOptions(LZMsgTypes.SWAP_USDT, 0);
            // Use LayerZero.
            _lzSend(
                DST_EID,
                _encodeMessage(balance),
                lzOptions,
                // Fee in the native gas and ZRO token.
                MessagingFee(msg.value, 0),
                // Refund address in case of a failed source message.
                payable(msg.sender)
            );
        }
    }

    /** @dev Quotes the gas needed to pay for the full omnichain transaction.
     * @return nativeFee Estimated gas fee in the native gas.
     * @return lzTokenFee Estimated gas fee in the ZRO token.
     */
    function quote() public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        // Check whether the quote is applied for making requests, which require cross-chain transporting.
        if (serverEnabled) {
            // No quote is applied.
            return (0, 0);
        }
        bytes memory payload = _encodeMessage(0);
        // Get options for LayerZero.
        bytes memory lzOptions = getLzOptions(LZMsgTypes.SWAP_USDT, 0);
        MessagingFee memory fee = _quote(DST_EID, payload, lzOptions, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }

    /// @inheritdoc ServerControlled
    function setServerEnable(bool enable) external override onlyOwner {
        serverEnabled = enable;
    }

    /// @inheritdoc ServerControlled
    function setAuthorizedServer(address server) external override onlyOwner {
        authorizedServer = server;
    }
}
