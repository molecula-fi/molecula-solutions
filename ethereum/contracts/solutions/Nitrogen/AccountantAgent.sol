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

/// @notice Pausable agent contract for the Ethereum Rebase token.
contract AccountantAgent is Ownable, IAccountant, IAgent, ZeroValueChecker {
    using SafeERC20 for IERC20;

    /// @dev Rebase token contract's address.
    address public immutable REBASE_TOKEN;

    /// @dev SupplyManager interface.
    ISupplyManager public immutable SUPPLY_MANAGER;

    /// @dev USDT token's address.
    IERC20 public immutable ERC20_TOKEN;

    /// @dev Account address that can pause the `requestDeposit` and `requestRedeem` functions.
    address public guardian;

    /// @dev Flag indicating whether the `requestDeposit` function is paused.
    bool public isRequestDepositPaused;

    /// @dev Flag indicating whether the `requestRedeem` function is paused.
    bool public isRequestRedeemPaused;

    /// @dev Error: `msg.sender` is not authorized for some function.
    error EBadSender();

    /// @dev Error: The `requestDeposit` function is called while being paused as the `isRequestDepositPaused` flag is set.
    error ERequestDepositPaused();

    /// @dev Error: The `requestRedeem` function is called while being paused as the `isRequestRedeemPaused` flag is set.
    error ERequestRedeemPaused();

    /// @dev Emitted when the `isRequestDepositPaused` flag is changed.
    /// @param newValue New value.
    event IsRequestDepositPausedChanged(bool newValue);

    /// @dev Emitted when the `isRequestRedeemPaused` flag is changed.
    /// @param newValue New value.
    event IsRequestRedeemPausedChanged(bool newValue);

    /// @dev Throws an error if called with the wrong sender.
    /// @param expectedSender Expected sender.
    modifier only(address expectedSender) {
        if (msg.sender != expectedSender) {
            revert EBadSender();
        }
        _;
    }

    /// @dev Check that `msg.sender` is the owner or guardian.
    modifier onlyAuthForPause() {
        if (msg.sender != owner() && msg.sender != guardian) {
            revert EBadSender();
        }
        _;
    }

    /**
     * @dev Initializes the contract setting the initializer address.
     * @param initialOwner Owner address.
     * @param rebaseTokenAddress Swap initializer contract's address.
     * @param supplyManagerAddress Supply Manager's contract address.
     * @param usdtAddress USDT token's address.
     * @param guardianAddress Guardian address that can pause the contract.
     */
    constructor(
        address initialOwner,
        address rebaseTokenAddress,
        address supplyManagerAddress,
        address usdtAddress,
        address guardianAddress
    )
        Ownable(initialOwner)
        checkNotZero(initialOwner)
        checkNotZero(rebaseTokenAddress)
        checkNotZero(supplyManagerAddress)
        checkNotZero(usdtAddress)
        checkNotZero(guardianAddress)
    {
        REBASE_TOKEN = rebaseTokenAddress;
        SUPPLY_MANAGER = ISupplyManager(supplyManagerAddress);
        ERC20_TOKEN = IERC20(usdtAddress);
        guardian = guardianAddress;
    }

    /**
     * @dev Emitted when processing deposits.
     * @param requestId Redemption operation unique identifier.
     * @param user User address.
     * @param value Deposited value.
     */
    function requestDeposit(
        uint256 requestId,
        address user,
        uint256 value
    ) external payable onlyZeroMsgValue only(REBASE_TOKEN) {
        // Check whether the `requestDeposit` function is paused.
        if (isRequestDepositPaused) {
            revert ERequestDepositPaused();
        }

        // Transfer the requested token value from the user.
        // slither-disable-next-line arbitrary-send-erc20
        ERC20_TOKEN.safeTransferFrom(user, address(this), value);

        // Approve to the Molecula Pool.
        ERC20_TOKEN.forceApprove(SUPPLY_MANAGER.getMoleculaPool(), value);

        // Call the SupplyManager's deposit method.
        uint256 shares = SUPPLY_MANAGER.deposit(address(ERC20_TOKEN), requestId, value);

        // Call the rebase token to confirm the deposit.
        IRebaseToken(REBASE_TOKEN).confirmDeposit(requestId, shares);

        // Emit an event to log the deposit operation.
        emit Deposit(requestId, value, shares);
    }

    /// @inheritdoc IAccountant
    function requestRedeem(
        uint256 requestId,
        uint256 shares
    ) external payable onlyZeroMsgValue only(REBASE_TOKEN) {
        // Check whether the `requestRedeem` function is paused.
        if (isRequestRedeemPaused) {
            revert ERequestRedeemPaused();
        }

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
    ) external payable only(address(SUPPLY_MANAGER)) onlyZeroMsgValue {
        // slither-disable-next-line arbitrary-send-erc20
        ERC20_TOKEN.safeTransferFrom(fromAddress, address(this), totalValue);
        // slither-disable-next-line unused-return
        IRebaseToken(REBASE_TOKEN).redeem(requestIds, values);
    }

    /// @inheritdoc IAccountant
    function confirmRedeem(address user, uint256 value) external only(REBASE_TOKEN) {
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
    ) external payable onlyZeroMsgValue only(address(SUPPLY_MANAGER)) {
        for (uint256 i = 0; i < users.length; i++) {
            IRebaseToken(REBASE_TOKEN).distribute(users[i], shares[i]);
        }
        // Emit an event to log operation.
        emit DistributeYield(users, shares);
    }

    /// @dev Change the guardian's address.
    /// @param newGuardian New guardian's address.
    function changeGuardian(address newGuardian) external onlyOwner checkNotZero(newGuardian) {
        guardian = newGuardian;
    }

    /// @dev Set a new value for the `isRequestDepositPaused` flag.
    /// @param newValue New value.
    function _setIsRequestDepositPaused(bool newValue) private {
        if (isRequestDepositPaused != newValue) {
            isRequestDepositPaused = newValue;
            emit IsRequestDepositPausedChanged(newValue);
        }
    }

    /// @dev Set a new value for the `isRequestRedeemPaused` flag.
    /// @param newValue New value.
    function _setIsRequestRedeemPaused(bool newValue) private {
        if (isRequestRedeemPaused != newValue) {
            isRequestRedeemPaused = newValue;
            emit IsRequestRedeemPausedChanged(newValue);
        }
    }

    /// @dev Pause the `requestDeposit` function.
    function pauseRequestDeposit() external onlyAuthForPause {
        _setIsRequestDepositPaused(true);
    }

    /// @dev Unpause the `requestDeposit` function.
    function unpauseRequestDeposit() external onlyOwner {
        _setIsRequestDepositPaused(false);
    }

    /// @dev Pause the `requestRedeem` function.
    function pauseRequestRedeem() external onlyAuthForPause {
        _setIsRequestRedeemPaused(true);
    }

    /// @dev Unpause the `requestRedeem` function.
    function unpauseRequestRedeem() external onlyOwner {
        _setIsRequestRedeemPaused(false);
    }

    /// @dev Pause the `requestDeposit` and `requestRedeem` functions.
    function pauseAll() external onlyAuthForPause {
        _setIsRequestDepositPaused(true);
        _setIsRequestRedeemPaused(true);
    }

    /// @dev Unpause the `requestDeposit` and `requestRedeem` functions.
    function unpauseAll() external onlyOwner {
        _setIsRequestDepositPaused(false);
        _setIsRequestRedeemPaused(false);
    }
}
