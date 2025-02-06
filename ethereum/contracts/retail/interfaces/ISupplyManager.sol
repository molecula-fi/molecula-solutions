// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;
/// @title Supply Manager's Interface
/// @notice Defines the functions and events required for pool data management.
interface ISupplyManager {
    /**
     * @dev Emitted when processing deposits.
     * @param requestId Deposit operation unique identifier.
     * @param agent Agent's address.
     * @param value A deposited amount.
     * @param shares Shares' amount to mint.
     */
    event Deposit(uint256 requestId, address agent, uint256 value, uint256 shares);

    /**
     * @dev Emitted when a user processing a withdrawal.
     * @param requestId Withdrawal operation unique identifier.
     * @param agent Agent's address.
     * @param value A withdrawn value.
     * @param shares A withdrawn shares.
     */
    event RedeemRequest(uint256 indexed requestId, address agent, uint256 shares, uint256 value);

    /**
     * @dev Event emitted when the redeem operation is executed.
     * @param requestIds Array of the request IDs.
     * @param values Array of the corresponding values.
     */
    event Redeem(uint256[] requestIds, uint256[] values);

    /**
     * @dev Event emitted when distributing yield.
     */
    event DistributeYield();

    /// @dev Error indicating no shares are available.
    error ENoShares();

    /// @dev Error indicating that the share has a too low price when withdrawing the value.
    error ETooLowSharePrice();

    /// @dev Error indicating that the share has a too high price when withdrawing the value.
    error ETooHighSharePrice();

    /// @dev Error indicating that the message sender is not an authorized agent.
    error ENotMyAgent();

    /// @dev Error indicating that the pool total supply equals zero.
    error EZeroTotalSupply();

    /**
     * @dev Process a deposit into the Pool.
     * @param token Deposited token ERC20 address.
     * @param requestId Deposit operation unique identifier.
     * @param value Deposit value.
     * @return shares Amount to mint.
     */
    function deposit(
        address token,
        uint256 requestId,
        uint256 value
    ) external returns (uint256 shares);

    /**
     * @dev Returns the molecula Pool address.
     * @return pool Molecula Pool address.
     */
    function getMoleculaPool() external view returns (address pool);

    /**
     * @dev Returns the total supply of the pool (TVL).
     * @return res Total pool supply.
     */
    function totalSupply() external view returns (uint256 res);

    /**
     * @dev Returns shares supply.
     * @return res Shares supply.
     */
    function totalSharesSupply() external view returns (uint256 res);

    /**
     * @dev Requests the redeem.
     * @param token Token ERC20 address.
     * @param requestId Redeem operation ID.
     * @param shares Shares to redeem.
     * @return value Value to redeem.
     */
    function requestRedeem(
        address token,
        uint256 requestId,
        uint256 shares
    ) external returns (uint256 value);

    /**
     * @dev Redeems the funds.
     * @param fromAddress Address to redeem from.
     * @param requestIds Redeem operation IDs.
     * @return token Token ERC20 address.
     * @return redeemedValue Redeemed value.
     */
    function redeem(
        address fromAddress,
        uint256[] memory requestIds
    ) external payable returns (address token, uint256 redeemedValue);

    /// @dev Returns Agents.
    /// @return List List of Agents.
    function getAgents() external view returns (address[] memory);
}
