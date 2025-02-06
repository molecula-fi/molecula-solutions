// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwftSwap} from "../../common/interfaces/ISwftSwap.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ServerControlled} from "../../common/ServerControlled.sol";

import {OptionsLZ} from "../../common/OptionsLZ.sol";
import {LZMsgTypes} from "../../common/LZMsgTypes.sol";

/// @notice Agent contract to call the SWFT Bridge.
contract WmUsdtToken is OApp, IERC20, ServerControlled, LZMsgTypes, OptionsLZ {
    using SafeERC20 for IERC20;

    /// @dev AgentLZ address.
    address public immutable AGENT;

    /// @dev Token total supply.
    uint256 public totalSupply;

    /// @dev The token holder address.
    address public poolKeeper;

    /// @dev Swap operation value.
    uint256 public swapValue;

    /// @dev LayerZero destination chain ID.
    uint32 public immutable DST_EID;

    /// @dev USDT token address.
    address public immutable USDT_TOKEN;

    /// @dev SWFT Bridge contract address.
    address public immutable SWFT_BRIDGE;

    /// @dev Swap destination address.
    string public swftDestination;

    /// @dev Allowance mapping.
    mapping(address => uint256) private _allowance;

    /// @dev Event: USDT Swap Request.
    /// @param value Number of tokens to swap.
    /// @param minReturnValue Minimum return value.
    event USDTSwapRequest(uint256 value, uint256 minReturnValue);

    /// @dev Event: wmUSDT Swap Request.
    /// @param value Number of tokens to swap.
    event WmUSDTSwapRequest(uint256 value);

    /// @dev Error: Insufficient supply.
    error ENotEnoughSupply();

    /// @dev Error: Zero balance.
    error EZeroBalance();

    /// @dev Error: Swap in progress.
    error ESwapInProgress();

    /// @dev Error: Swap not in progress.
    error ESwapNotInProgress();

    /// @dev Error: Wrong agent.
    error EWrongAgent();

    /// @dev Error: Only token keeper.
    error EOnlyPoolKeeper();

    /// @dev Error: Not approved.
    error ENotApproved();

    /// @dev Modifier that checks whether the caller is the server.
    modifier onlyAgent() {
        if (msg.sender != AGENT) {
            revert EWrongAgent();
        }
        _;
    }

    /**
     * @dev Addresses Config struct.
     * @param initialOwner Owner address.
     * @param safeVaultAddress Safe Vault address.
     * @param agentAddress Server address.
     * @param poolKeeperAddress Pool keeper contract address.
     * @param server Server address.
     */
    struct AddressesConfig {
        address initialOwner;
        address agentAddress;
        address poolKeeperAddress;
        address server;
    }

    /**
     * @dev LayerZero Config struct.
     * @param endpoint LayerZero endpoint contract address.
     * @param authorizedLZConfigurator Authorized LayerZero configurator address.
     * @param lzBaseOpt LayerZero call options.
     * @param lzDstEid LayerZero destination chain ID.
     */
    struct LayerZeroConfig {
        address endpoint;
        address authorizedLZConfigurator;
        bytes lzBaseOpt;
        uint32 lzDstEid;
    }

    /**
     * @dev Swft Config struct.
     * @param usdtTokenAddress USDT token address.
     * @param swftBridgeAddress SWFT Bridge contract address.
     * @param swftDest Swap destination address.
     */
    struct SwftConfig {
        address usdtTokenAddress;
        address swftBridgeAddress;
        string swftDest;
    }

    /**
     * @dev Initializes the contract setting the initializer address.
     * @param initialSupply Initial supply.
     * @param addressesConfig Addresses Config struct.
     * @param layerZeroConfig LayerZero Config struct.
     * @param swftConfig Swft Config struct.
     */
    constructor(
        uint256 initialSupply,
        AddressesConfig memory addressesConfig,
        LayerZeroConfig memory layerZeroConfig,
        SwftConfig memory swftConfig
    )
        OApp(layerZeroConfig.endpoint, addressesConfig.initialOwner)
        ServerControlled(addressesConfig.server)
        OptionsLZ(
            addressesConfig.initialOwner,
            layerZeroConfig.authorizedLZConfigurator,
            layerZeroConfig.lzBaseOpt
        )
    {
        totalSupply = initialSupply;

        AGENT = addressesConfig.agentAddress;
        poolKeeper = addressesConfig.poolKeeperAddress;

        DST_EID = layerZeroConfig.lzDstEid;

        USDT_TOKEN = swftConfig.usdtTokenAddress;
        SWFT_BRIDGE = swftConfig.swftBridgeAddress;
        swftDestination = swftConfig.swftDest;
    }

    /**
     * @dev Called when the data is received from the protocol. It overrides the equivalent function in the parent contract.
     * Protocol messages are defined as packets, comprised of the following parameters. Call on deposit.
     * @param _origin Struct containing the information about where the packet came from.
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

        _confirmSwapUsdt(_decodeMessage(payload));
    }

    /**
     * @dev Confirms the swap operation.
     * @param value Number of tokens to swap.
     */
    function confirmSwapUsdt(uint256 value) external serverIsEnabled onlyOwner {
        _confirmSwapUsdt(value);
    }

    /**
     * @dev Confirms the swap operation.
     * @param value Number of tokens to swap.
     */
    function _confirmSwapUsdt(uint256 value) internal {
        // Align the swap value.
        totalSupply = value;

        // Finish the swap operation.
        swapValue = 0;
    }

    /**
     * @dev Gets the specified user's Pool token balance.
     * @param user User's address.
     * @return balance Number of Pool tokens held by the user.
     */
    function balanceOf(address user) external view returns (uint256 balance) {
        if (user == poolKeeper) {
            balance = totalSupply;
        } else {
            balance = 0;
        }
    }

    /**
     * @dev Sets the token keeper address.
     * @param poolKeeperAddress Token keeper contract address.
     */
    function setPoolKeeper(address poolKeeperAddress) external onlyOwner {
        poolKeeper = poolKeeperAddress;
    }

    /**
     * @dev Mints token.
     * @param value A value to mint.
     */
    function mint(uint256 value) external onlyAgent {
        totalSupply += value;
    }

    /**
     * @dev Burns tokens.
     * @param value A value to burn.
     */
    function burn(uint256 value) external onlyAgent {
        // Check the current swap status.
        // Note:
        // - We burn tokens during the redemption that leverages LayerZero.
        // - To avoid concurrency issues, we "blocK" all redeem operations until the swap is completed.
        if (isSwapInProgress()) {
            revert ESwapInProgress();
        }

        // Ensure the value is not greater than the total supply.
        if (value > totalSupply) {
            revert ENotEnoughSupply();
        }

        // Ensure the value is not greater than the sender allowance.
        if (value > _allowance[msg.sender]) {
            revert ENotApproved();
        }

        _allowance[msg.sender] -= value;
        totalSupply -= value;
    }

    /**
     * @dev Transfers tokens.
     * @param to Tokens recipient's address.
     * @param value Amount to transfer.
     * @return result Transaction result.
     */
    function transfer(address to, uint256 value) external pure returns (bool result) {
        to;
        value;
        // Do nothing.
        return true;
    }

    /**
     * @dev Transfers tokens from one address to another.
     * @param from Tokens sender's address.
     * @param to Tokens recipient's address.
     * @param value Amount to transfer.
     * @return result Transaction result.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external pure returns (bool result) {
        from;
        to;
        value;
        // Do nothing.
        return true;
    }

    /**
     * @dev Approves a spender.
     * @param spender Spender to be approved.
     * @param value Token amount the spender can expend.
     * @return result Result of the operation.
     */
    function approve(address spender, uint256 value) external returns (bool result) {
        if (msg.sender == poolKeeper) {
            _allowance[spender] = value;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns the user's allowance.
     * @param owner User whose allowance is to be returned.
     * @param spender User whose allowance is to be returned.
     * @return result User's allowance.
     */
    function allowance(address owner, address spender) external view returns (uint256 result) {
        if (owner == poolKeeper) {
            return _allowance[spender];
        } else {
            return 0;
        }
    }

    /**
     * @dev Returns the token's decimals.
     * @return tokenDecimals Token's decimals.
     */
    function decimals() external pure returns (uint8 tokenDecimals) {
        return 6;
    }

    /**
     * @dev Returns the name of the token.
     * @return tokenName Token name.
     */
    function name() public pure returns (string memory tokenName) {
        return "Wrapped Molecula USDT";
    }

    /**
     * @dev Returns the token symbol. Usually a shorter version of its name.
     * @return tokenSymbol Token symbol.
     */
    function symbol() public pure virtual returns (string memory tokenSymbol) {
        return "wmUSDT";
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
     * @dev Request the wmUSDT -> USDT swap operation.
     * @param value Number of tokens to swap.
     */
    function requestToSwapWmUSDT(uint256 value) external payable onlyAuthorizedServer {
        // Check the current swap status.
        if (isSwapInProgress()) {
            revert ESwapInProgress();
        }
        // Check if there is enough wmUSDT.
        if (totalSupply < value) {
            revert ENotEnoughSupply();
        }
        if (value > _allowance[address(this)]) {
            revert ENotApproved();
        }
        // Decrease the approve value.
        _allowance[address(this)] -= value;

        // Set the swap value.
        swapValue = value;

        if (!serverEnabled) {
            // Get options for LayerZero.
            bytes memory lzOptions = getLzOptions(LZMsgTypes.SWAP_WMUSDT, 0);
            // Use LayerZero.
            _lzSend(
                DST_EID,
                _encodeMessage(value),
                lzOptions,
                // Fee in the native gas and ZRO token.
                MessagingFee(msg.value, 0),
                // Refund address in case of a failed source message.
                payable(msg.sender)
            );
        }

        // Emit the event.
        emit WmUSDTSwapRequest(value);
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
        bytes memory lzOptions = getLzOptions(LZMsgTypes.SWAP_WMUSDT, 0);
        MessagingFee memory fee = _quote(DST_EID, payload, lzOptions, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }

    /**
     * @dev Confirm the wmUSDT -> USDT swap operation.
     */
    function confirmSwapWmUSDT() external onlyAuthorizedServer {
        // Get the USDT balance.
        uint256 balance = IERC20(USDT_TOKEN).balanceOf(address(this));
        // slither-disable-next-line incorrect-equality
        if (balance == 0) {
            revert EZeroBalance();
        }

        // Burn the swap value.
        totalSupply -= swapValue;
        swapValue = 0;

        // Transfer USDT.
        IERC20(USDT_TOKEN).safeTransfer(poolKeeper, balance);
    }

    /**
     * @dev Request the USDT -> wmUSDT swap operation.
     * @param value Number of tokens to swap.
     * @param minReturnValue Minimum return value.
     */
    function requestToSwapUSDT(
        uint256 value,
        uint256 minReturnValue
    ) external onlyAuthorizedServer {
        // Check the current swap status.
        if (isSwapInProgress()) {
            revert ESwapInProgress();
        }

        // Get USDT from token keeper.
        // slither-disable-next-line arbitrary-send-erc20
        IERC20(USDT_TOKEN).safeTransferFrom(poolKeeper, address(this), value);

        // Transfer to the Bridge.
        _transferToSwftBridge(value, minReturnValue);
    }

    /**
     * @dev Resend the USDT to wmUSDT swap operation request in case of the SWFT failure.
     * @param value Number of tokens to swap.
     * @param minReturnValue Minimum return value.
     */
    function resendRequestToSwapUSDT(
        uint256 value,
        uint256 minReturnValue
    ) external onlyAuthorizedServer {
        // Check the current swap status.
        if (!isSwapInProgress()) {
            revert ESwapNotInProgress();
        }

        // Restore the total supply.
        totalSupply -= swapValue;

        // Transfer to the Bridge.
        _transferToSwftBridge(value, minReturnValue);
    }

    /**
     * @dev Transfers tokens to the SWFT Bridge.
     * @param value USDT amount to transfer.
     * @param minReturnValue Minimum return value.
     */
    function _transferToSwftBridge(uint256 value, uint256 minReturnValue) internal {
        // Save the swap value.
        swapValue = value;
        // Mint wmUSDT to stabilize the Molecula Pool TVL, as this amount of USDT will be transferred to the SWFT Bridge immediately.
        totalSupply += value;

        // Approve to the Bridge.
        IERC20(USDT_TOKEN).forceApprove(SWFT_BRIDGE, value);
        // Call the Bridge.
        ISwftSwap(SWFT_BRIDGE).swap(
            USDT_TOKEN,
            "USDT(TRON)", // https://github.com/SwftCoins/GPT4-Plugin/blob/274765ca07c7e055186b37dcef9da50cf32c6d14/token_files/coin_list.json#L455
            swftDestination,
            value,
            minReturnValue
        );

        // Emit the event.
        emit USDTSwapRequest(value, minReturnValue);
    }

    /**
     * @dev Sets the swap destination address.
     * @param dst Swap destination address.
     */
    function setSwftDestination(string memory dst) public onlyOwner {
        swftDestination = dst;
    }

    /**
     * @dev Check if the swap is in progress.
     * @return result Swap status. `true` if swap is in progress, `false` if not.
     */
    function isSwapInProgress() public view returns (bool result) {
        return swapValue != 0;
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
