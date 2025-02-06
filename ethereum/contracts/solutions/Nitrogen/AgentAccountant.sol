// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAgent} from "../../retail/interfaces/IAgent.sol";
import {ISupplyManager} from "../../retail/interfaces/ISupplyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAccountant} from "../../retail/interfaces/IAccountant.sol";
import {IRebaseToken} from "../../retail/interfaces/IRebaseToken.sol";
import {ZeroValueChecker} from "../../common/ZeroValueChecker.sol";

/// @notice Agent contract for the Ethereum Rebase token.
contract AgentAccountant is Ownable, IAccountant, IAgent, ZeroValueChecker {
    using SafeERC20 for IERC20;

    /// @dev Rebase token contract address.
    address public rebaseToken;

    /// @dev SupplyManager interface.
    ISupplyManager public immutable SUPPLY_MANAGER;

    /// @dev USDT token address.
    IERC20 public immutable ERC20_TOKEN;

    /// @dev Error: Invalid swap initializer address.
    error EInvalidRebaseToken();

    /// @dev Error: Not my supply manager.
    error ENotMySupplyManager();

    /// @dev Modifier that checks whether the caller is the Supply Manager.
    modifier onlySupplyManager() {
        if (msg.sender != address(SUPPLY_MANAGER)) {
            revert ENotMySupplyManager();
        }
        _;
    }
    /**
     * @dev Initializes the contract setting the initializer address.
     * @param initialOwner Owner address.
     * @param rebaseTokenAddress Swap initializer contract address.
     * @param supplyManagerAddress Supply Manager's contract address.
     * @param usdtAddress USDT token address.
     */
    constructor(
        address initialOwner,
        address rebaseTokenAddress,
        address supplyManagerAddress,
        address usdtAddress
    )
        Ownable(initialOwner)
        checkNotZero(initialOwner)
        checkNotZero(rebaseTokenAddress)
        checkNotZero(supplyManagerAddress)
        checkNotZero(usdtAddress)
    {
        rebaseToken = rebaseTokenAddress;
        SUPPLY_MANAGER = ISupplyManager(supplyManagerAddress);
        ERC20_TOKEN = IERC20(usdtAddress);
    }

    /**
     * @dev Sets the swap initializer address.
     * @param rebaseTokenAddress Swap initializer contract address.
     */
    function setRebaseToken(
        address rebaseTokenAddress
    ) external onlyOwner checkNotZero(rebaseTokenAddress) {
        rebaseToken = rebaseTokenAddress;
    }

    /**
     * @dev Modifier that checks whether the caller is the swap initializer.
     */
    modifier onlyRebaseToken() {
        if (rebaseToken != msg.sender) {
            revert EInvalidRebaseToken();
        }
        _;
    }

    /**
     * @dev Emitted when processing deposits.
     * @param requestId Withdrawal operation unique identifier.
     * @param user User address.
     * @param value A deposited value.
     */
    function requestDeposit(
        uint256 requestId,
        address user,
        uint256 value
    ) external payable onlyZeroMsgValue onlyRebaseToken {
        // Transfer from user
        // slither-disable-next-line arbitrary-send-erc20
        ERC20_TOKEN.safeTransferFrom(user, address(this), value);

        // Approve to the Molecula Pool.
        ERC20_TOKEN.forceApprove(SUPPLY_MANAGER.getMoleculaPool(), value);

        // Call the Supply Manager's deposit method.
        uint256 shares = SUPPLY_MANAGER.deposit(address(ERC20_TOKEN), requestId, value);

        // Call the rebase token to confirm the deposit.
        IRebaseToken(rebaseToken).confirmDeposit(requestId, shares);

        // Emit an event to log the deposit operation.
        emit Deposit(requestId, value, shares);
    }

    /// @inheritdoc IAccountant
    function requestRedeem(
        uint256 requestId,
        uint256 shares
    ) external payable onlyZeroMsgValue onlyRebaseToken {
        // Call the Supply Manager's `requestRedeem` method.
        uint256 value = SUPPLY_MANAGER.requestRedeem(address(ERC20_TOKEN), requestId, shares);
        // Emit an event to log the redeem operation.
        emit RedeemRequest(requestId, shares, value);
    }

    /// @inheritdoc IAgent
    // slither-disable-next-line locked-ether
    function redeem(
        address fromAddress,
        uint256[] memory requestIds,
        uint256[] memory values,
        uint256 totalValue
    ) external payable onlySupplyManager onlyZeroMsgValue {
        // slither-disable-next-line arbitrary-send-erc20
        ERC20_TOKEN.safeTransferFrom(fromAddress, address(this), totalValue);
        // slither-disable-next-line unused-return
        IRebaseToken(rebaseToken).redeem(requestIds, values);
    }

    /**
     * @dev Changes the Rebase Token owner.
     * @param newOwner New owner
     */
    function changeRebaseTokenOwner(address newOwner) external onlyOwner {
        Ownable(rebaseToken).transferOwnership(newOwner);
    }

    /// @inheritdoc IAccountant
    function confirmRedeem(address user, uint256 value) external onlyRebaseToken {
        ERC20_TOKEN.safeTransfer(user, value);
    }

    /// @inheritdoc IAgent
    function getERC20Token() external view returns (address token) {
        return address(ERC20_TOKEN);
    }

    /// @inheritdoc IAgent
    // slither-disable-next-line locked-ether
    function distribute(
        address[] memory users,
        uint256[] memory shares
    ) external payable onlyZeroMsgValue onlySupplyManager {
        for (uint256 i = 0; i < users.length; i++) {
            IRebaseToken(rebaseToken).distribute(users[i], shares[i]);
        }
        // Emit an event to log operation.
        emit DistributeYield(users, shares);
    }
}
