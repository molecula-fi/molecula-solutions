// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {IAccountant} from "./interfaces/IAccountant.sol";
import {IRebaseTokenErrors} from "./interfaces/IRebaseTokenErrors.sol";
import {IRebaseTokenEvents} from "./interfaces/IRebaseTokenEvents.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {OperationStatus} from "./structures/OperationStatus.sol";
import {RebaseERC20Permit} from "./RebaseERC20Permit.sol";
import {RedeemOperationInfo, DepositOperationInfo} from "./structures/OperationInfo7540.sol";

contract RebaseTokenCommon is
    IRebaseToken,
    RebaseERC20Permit,
    IRebaseTokenEvents,
    IRebaseTokenErrors
{
    /// @dev Last operation ID tracked by the contract.
    uint256 private _lastOperationIndex = 0;
    /// @dev Mapping operation ID to the deposit information.
    mapping(uint256 => DepositOperationInfo) public depositRequests;
    /// @dev Mapping operation ID to the redeem operation information.
    mapping(uint256 => RedeemOperationInfo) public redeemRequests;
    /// @dev Accountant address.
    IAccountant public accountant;
    /// @dev Minimum deposit value.
    uint256 public minDepositValue;
    /// @dev Minimum redeem operation value.
    uint256 public minRedeemValue;
    /// @dev Checks if an operator is approved by the controller.
    mapping(address controller => mapping(address operator => bool)) public isOperator;

    /**
     * @dev Throws an error if an account that is not the Accountant calls the function.
     */
    modifier onlyAccountant() {
        if (address(accountant) != msg.sender) {
            revert EOnlyAccountant();
        }
        _;
    }

    /// @dev Throws an error if a message sender is not the owner's operator.
    /// @param owner Owner of the assets or shares.
    modifier onlyOperator(address owner) {
        if (owner != msg.sender && !isOperator[owner][msg.sender]) {
            revert EBadOwner(msg.sender, owner);
        }
        _;
    }

    /**
     * @dev Constructor for initializing the contract.
     * @param initialOwner Smart contract owner address.
     * @param accountantAddress Accountant address.
     * @param initialShares Shares' amount to mint.
     * @param oracleAddress Oracle contract address.
     * @param tokenName Token name.
     * @param tokenSymbol Token symbol.
     * @param tokenDecimals Token decimals.
     * @param minDeposit Minimum deposit value.
     * @param minRedeem Minimum redeem operation value.
     */
    constructor(
        address initialOwner,
        address accountantAddress,
        uint256 initialShares,
        address oracleAddress,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        uint256 minDeposit,
        uint256 minRedeem
    )
        RebaseERC20Permit(
            initialShares,
            oracleAddress,
            initialOwner,
            tokenName,
            tokenSymbol,
            tokenDecimals
        )
    {
        accountant = IAccountant(accountantAddress);
        _setMinDepositValue(minDeposit);
        _setMinRedeemValue(minRedeem);
    }

    /**
     * @dev Creates a new deposit request.
     * @param assets Amount of assets to deposit.
     * @param controller Controller of the request: the beneficiary of the deposit.
     * @param owner Owner of assets.
     * @return requestId Operation ID.
     */
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public payable virtual onlyOperator(owner) returns (uint256 requestId) {
        // Check deposit value.
        if (assets < minDepositValue) {
            revert ETooLowDepositValue(minDepositValue);
        }

        // Generate an ID for each new operation.
        requestId = _generateOperationId();

        // Check if the deposit operation already exists.
        if (depositRequests[requestId].status != OperationStatus.None) {
            revert EBadOperationParameters();
        }

        // Create a new deposit operation with the user and deposit value.
        DepositOperationInfo memory depositInfo = DepositOperationInfo(
            controller,
            assets,
            OperationStatus.Pending
        );
        // Store the deposit operation in the `depositRequests` mapping.
        depositRequests[requestId] = depositInfo;

        // Call the Accountant to request the deposit.
        accountant.requestDeposit{value: msg.value}(requestId, owner, assets);

        // Emit an event to log the deposit request.
        emit DepositRequest(controller, owner, requestId, msg.sender, assets);
        return requestId;
    }

    /**
     * @dev Returns the amount of assets that was deposited.
     * @param requestId Corresponding ID.
     * @param controller Corresponding controller.
     * @return assets Amount of assets.
     */
    function pendingDepositRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 assets) {
        controller;
        if (depositRequests[requestId].status == OperationStatus.Pending) {
            return depositRequests[requestId].assets;
        }
        return 0;
    }

    /**
     * @dev Returns the amount of assets that can be claimed.
     * @param requestId Corresponding ID.
     * @param controller Corresponding controller.
     * @return assets Amount of assets.
     */
    function claimableDepositRequest(
        uint256 requestId,
        address controller
    ) external pure returns (uint256 assets) {
        requestId;
        controller;
        return 0;
    }

    /**
     * @dev Creates a new redeem operation request.
     * @param value Value to withdraw.
     * @param controller Owner of the request, who can manage any actions related to the request.
     * @param owner User's address.
     * @return requestId Operation ID.
     */
    function requestWithdrawal(
        uint256 value,
        address controller,
        address owner
    ) public payable virtual returns (uint256 requestId) {
        uint256 shares = convertToShares(value);
        return requestRedeem(shares, controller, owner);
    }

    /**
     * @dev Creates a new redeem operation request.
     * @param shares Amount of shares to withdraw.
     * @param controller Controller of the Request: the beneficiary of the redeem operation.
     * @param owner Owner of assets.
     * @return requestId Operation ID.
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public payable virtual onlyOperator(owner) returns (uint256 requestId) {
        // Set the shares' amount equal to the user's shares if the shares' amount is greater than the user's shares.
        uint256 userShares = sharesOf(owner);
        if (shares > userShares) {
            shares = userShares;
        }

        // Check the redeem operation value.
        if (shares < minRedeemValue) {
            revert ETooLowRedeemValue(minRedeemValue);
        }

        // Generate an ID for each new operation.
        requestId = _generateOperationId();

        // Check whether the redeem operation exists.
        if (redeemRequests[requestId].status != OperationStatus.None) {
            revert EBadOperationParameters();
        }

        // Burn the user's shares.
        _burn(owner, shares);

        // Create a new redeem operation.
        RedeemOperationInfo memory redeemInfo = RedeemOperationInfo(
            controller,
            shares,
            OperationStatus.Pending
        );
        // Store the redeem operation in the `redeemRequests` mapping.
        redeemRequests[requestId] = redeemInfo;

        // Call the Accountant to request the redeem operation.
        accountant.requestRedeem{value: msg.value}(requestId, shares);

        // Emit an event to log the redeem operation request.
        emit RedeemRequest(controller, owner, requestId, msg.sender, shares);
        return requestId;
    }

    /**
     * @dev Executes the redeem operation.
     * @param operationIds Array of the operation IDs.
     * @param values Array of values.
     * @return totalValue Total value to redeem.
     */
    function redeem(
        uint256[] memory operationIds,
        uint256[] memory values
    ) external onlyAccountant returns (uint256 totalValue) {
        // Iterate through the operation IDs and values.
        for (uint256 i = 0; i < operationIds.length; i++) {
            // Check if the operation is pending.
            // Do nothing otherwise, since the operation might be already processed.
            if (redeemRequests[operationIds[i]].status == OperationStatus.Pending) {
                // Set the redeem operation value to `val`.
                redeemRequests[operationIds[i]].val = values[i];
                // Set status to `ReadyToConfirm`.
                redeemRequests[operationIds[i]].status = OperationStatus.ReadyToConfirm;
                // Calculate the redeem operation total value.
                totalValue += values[i];
            }
        }

        emit Redeem(operationIds, values);

        return totalValue;
    }

    /**
     * @dev Returns the amount of assets that was redeemed.
     * @param requestId Corresponding ID.
     * @param controller Corresponding controller.
     * @return shares Amount of assets.
     */
    function pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) external view returns (uint256 shares) {
        controller;
        if (redeemRequests[requestId].status == OperationStatus.Pending) {
            return redeemRequests[requestId].val;
        }
        return 0;
    }

    /**
     * @dev Returns the amount of assets that can be redeemed.
     * @param requestId Corresponding ID.
     * @param controller Corresponding controller.
     * @return shares Amount of assets.
     */
    function claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) external pure returns (uint256 shares) {
        requestId;
        controller;
        return 0;
    }

    /**
     * @dev Approves or disapproves an operator for a controller.
     * We don't support the operator logic here.
     * @param operator Corresponding operator.
     * @param approved Approval.
     * @return result Approval result.
     */
    function setOperator(address operator, bool approved) public returns (bool result) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    /**
     * @dev Generates an operation ID.
     * @return id Operation ID.
     */
    function _generateOperationId() internal returns (uint256 id) {
        _lastOperationIndex += 1;
        bytes32 h = keccak256(abi.encodePacked(address(this), block.chainid, _lastOperationIndex));
        return uint256(h);
    }

    /**
     * @dev Confirms a deposit.
     * @param requestId Operation ID.
     * @param shares Shares' amount.
     */
    function confirmDeposit(uint256 requestId, uint256 shares) external onlyAccountant {
        // Check if the operation exists.
        if (depositRequests[requestId].status != OperationStatus.Pending) {
            revert EBadOperationParameters();
        }
        // Get the user's address to proceed with the deposit operation.
        address user = depositRequests[requestId].addr;

        // Save the operation status.
        depositRequests[requestId].status = OperationStatus.Confirmed;

        // Value minted for the user.
        uint256 value = 0;
        // If we have shares, mint then.
        if (shares > 0) {
            // Convert the shares to the value.
            value = convertToAssets(shares);

            // Mint shares for the user.
            _mint(user, shares);
        }

        // Emit an event to log the deposit confirmation.
        emit DepositConfirm(requestId, user, value, shares);
    }

    /**
     * @dev Confirms a redeem operation.
     * @param requestId Operation ID.
     */
    function confirmRedeem(uint256 requestId) external {
        if (redeemRequests[requestId].status != OperationStatus.ReadyToConfirm) {
            // Revert the transaction with an error if the redeem operation does not exist.
            revert EBadOperationParameters();
        }
        // Save the operation status.
        redeemRequests[requestId].status = OperationStatus.Confirmed;

        // Call the Accountant to confirm the redeem operation.
        accountant.confirmRedeem(redeemRequests[requestId].addr, redeemRequests[requestId].val);

        // Emit an event to log redeem operation confirmation.
        emit RedeemConfirm(
            requestId,
            redeemRequests[requestId].addr,
            redeemRequests[requestId].val
        );
    }

    /**
     * @dev Sets the Accountant address.
     * @param accountantAddress Accountant address.
     */
    function setAccountant(address accountantAddress) external onlyOwner {
        accountant = IAccountant(accountantAddress);
    }

    /**
     * @dev Sets the minimum deposit value.
     * @param minDeposit Minimum deposit value.
     */
    function _setMinDepositValue(uint256 minDeposit) internal {
        if (minDeposit == 0) revert EZeroMinDepositValue();
        minDepositValue = minDeposit;
    }

    /**
     * @dev Sets the minimum deposit value.
     * @param minDeposit Minimum deposit value.
     */
    function setMinDepositValue(uint256 minDeposit) external onlyOwner {
        _setMinDepositValue(minDeposit);
    }

    /**
     * @dev Sets the minimum redeem operation value.
     * @param minRedeem Minimum redeem operation value.
     */
    function _setMinRedeemValue(uint256 minRedeem) internal {
        if (minRedeem == 0) revert EZeroMinRedeemValue();
        minRedeemValue = minRedeem;
    }

    /**
     * @dev Sets the minimum redeem operation value.
     * @param minRedeem Minimum redeem operation value.
     */
    function setMinRedeemValue(uint256 minRedeem) external onlyOwner {
        _setMinRedeemValue(minRedeem);
    }

    /// @inheritdoc IRebaseToken
    function distribute(address party, uint256 shares) external onlyAccountant {
        // Mint shares for the user.
        _mint(party, shares);
    }
}
