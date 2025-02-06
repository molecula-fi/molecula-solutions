// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ISupplyManager} from "./interfaces/ISupplyManager.sol";
import {IMoleculaPool} from "./interfaces/IMoleculaPool.sol";
import {IOracle} from "../common/interfaces/IOracle.sol";
import {IAgent} from "./interfaces/IAgent.sol";
import {ZeroValueChecker} from "../common/ZeroValueChecker.sol";

uint256 constant APY_FACTOR = 10_000;
uint256 constant FULL_PORTION = 1e18;

enum OperationStatus {
    None,
    Pending,
    Confirmed,
    Reverted
}
/**
 * @dev Struct to store the redeem operation information.
 * @param agent Agent address associated with the operation.
 * @param value Operation-associated value on the withdrawal.
 * @param status Operation status.
 */
struct RedeemOperationInfo {
    address agent;
    uint256 value;
    OperationStatus status;
}

/**
 * @dev Struct to store the yield distributed for the Agent parties.
 * @param agent Agent address.
 * @param parties Yield distribution parties.
 * @param ethValue ETH value.
 */
struct AgentInfo {
    address agent;
    Party[] parties;
    uint256 ethValue;
}

/**
 * @dev Struct to store the yield for a party.
 * @param party User address.
 * @param portion Yield portion.
 */
struct Party {
    address party;
    uint256 portion;
}

/// @title Supply Manager.
/// @notice Manages the pool data.
contract SupplyManager is Ownable, ISupplyManager, IOracle, ZeroValueChecker {
    /// @dev Total staking shares supply.
    uint256 public totalSharesSupply;

    /// @dev Total staking supply.
    uint256 public totalDepositedSupply;

    /// @dev Protocol-locked yield in shares, which are to be distributed later.
    uint256 public lockedYieldShares;

    /// @dev Mapping of the authorized Agents.
    mapping(address => bool) public agents;

    /// @dev Mapping of the authorized Agents.
    address[] public agentsArray;

    /// @dev Molecula Pool address.
    /// @custom:security non-reentrant
    IMoleculaPool public moleculaPool;

    /// @dev Mapping of redemptions.
    mapping(uint256 => RedeemOperationInfo) public redeemRequests;

    /// @dev APY formatter parameter, where
    /// (apyFormatter / APY_FACTOR) * 100% is the percentage of revenue retained by all mUSD holder.
    uint256 public apyFormatter;

    /// @dev Authorized Yield Distributor.
    address public authorizedYieldDistributor;

    /// @dev Throws an error if the caller is not the Molecula Pool.
    error ENotMoleculaPool();

    /// @dev Throws an error if used the wrong Agent.
    error EWrongAgent();

    /// @dev Throws an error if the operation status is incorrect.
    error EBadOperationStatus();

    /// @dev Throws an error if the sum of portion is not equal to `1`.
    error EWrongPortion();

    /// @dev Throws an error if the Agent already exists in the parties' list.
    error EDuplicateAgent();

    /// @dev Throws an error if the parties' list is empty.
    error EEmptyParties();

    /// @dev Throws an error if the APY is invalid.
    error EInvalidAPY();

    /// @dev Throws an error if the Yield Distributor is not authorized.
    error ENotAuthorizedYieldDistributor();

    /// @dev Throws an error if the yield amount is not a positive value.
    error ENoRealYield();

    /// @dev Throws an error if the agent status has already been set.
    error EAgentStatusIsAlreadySet();

    /**
     * @dev Throws an error if the caller is not the authorized Agent.
     */
    modifier onlyAgent() {
        if (!agents[msg.sender]) {
            revert ENotMyAgent();
        }
        _;
    }

    /**
     * @dev Throws an error if the caller is not the Molecula Pool.
     */
    modifier onlyMoleculaPool() {
        if (address(moleculaPool) != msg.sender) {
            revert ENotMoleculaPool();
        }
        _;
    }

    /**
     * @dev Throws an error if the caller is not the authorized Yield Distributor.
     */
    modifier onlyAuthorizedYieldDistributor() {
        if (msg.sender != authorizedYieldDistributor) {
            revert ENotAuthorizedYieldDistributor();
        }
        _;
    }

    /**
     * @dev Constructor.
     * @param initialOwner Smart contract owner address.
     * @param authorizedYieldDistributorAddress Authorized Yield Distributor address.
     * @param moleculaPoolAddress Molecula Pool contract address.
     * @param apy APY value.
     */
    constructor(
        address initialOwner,
        address authorizedYieldDistributorAddress,
        address moleculaPoolAddress,
        uint256 apy
    )
        Ownable(initialOwner)
        checkNotZero(initialOwner)
        checkNotZero(authorizedYieldDistributorAddress)
        checkNotZero(moleculaPoolAddress)
    {
        moleculaPool = IMoleculaPool(moleculaPoolAddress);
        totalDepositedSupply = moleculaPool.totalSupply();
        if (totalDepositedSupply == 0) {
            revert EZeroTotalSupply();
        }
        totalSharesSupply = totalDepositedSupply;
        _checkApyFormatter(apy);
        apyFormatter = apy;
        authorizedYieldDistributor = authorizedYieldDistributorAddress;
    }

    /// @inheritdoc ISupplyManager
    function deposit(
        address token,
        uint256 requestId,
        uint256 value
    ) external onlyAgent returns (uint256 shares) {
        // Save the total supply value at the start of the operation.
        uint256 startTotalSupply = totalSupply();

        // Call the Molecula Pool to deposit the value.
        uint256 formattedValue18 = moleculaPool.deposit(token, requestId, msg.sender, value);

        // Calculate the shares' amount to add upon the deposit operation by dividing the value by the `sharePrice` value.
        shares = (formattedValue18 * totalSharesSupply) / startTotalSupply;

        // Increase the total shares' supply amount.
        totalSharesSupply += shares;

        // Increase the total deposited supply value.
        totalDepositedSupply += formattedValue18;

        // Emit the deposit event.
        emit Deposit(requestId, msg.sender, value, shares);

        // Return the shares' amount.
        return shares;
    }

    /// @inheritdoc ISupplyManager
    function requestRedeem(
        address token,
        uint256 requestId,
        uint256 shares
    ) external onlyAgent returns (uint256 value) {
        // Ensure that shares can be withdrawn.
        if (shares > totalSharesSupply) {
            revert ENoShares();
        }

        // Check status of the operation.
        if (redeemRequests[requestId].status != OperationStatus.None) {
            revert EBadOperationStatus();
        }

        // Get the current total supply.
        uint256 currentTotalSupply = totalSupply();

        // Convert shares to the value before applying any changes to the contract values.
        value = (shares * currentTotalSupply) / totalSharesSupply;

        // Prepare the operation yield variables.
        uint256 operationYield = 0;
        uint256 operationYieldShares = 0;

        // Ensure that the operation has generated yield and lock it if it has.
        if (apyFormatter != 0 && totalDepositedSupply < currentTotalSupply) {
            // Calculate an operation yield value, which can be later distributed as a protocol income.
            // The operation yield must be equal to `actualIncome * (APY_FACTOR - apyFormatter)`.
            // The simplified formula: `userIncome / apyFormatter * (APY_FACTOR - apyFormatter)`.
            // The detailed formula: `((shares * (totalSupply - totalDepositedSupply)) / totalSharesSupply) / apyFormatter * (APY_FACTOR - apyFormatter)`.
            operationYield =
                (shares *
                    (currentTotalSupply - totalDepositedSupply) *
                    (APY_FACTOR - apyFormatter)) /
                (totalSharesSupply * apyFormatter);

            // Present the operation yield as locked yield shares, which are to be distributed later.
            // slither-disable-next-line divide-before-multiply
            operationYieldShares = (operationYield * totalSharesSupply) / currentTotalSupply;

            // Update the locked yield shares by increasing it by the operation yield shares' amount.
            lockedYieldShares += operationYieldShares;
        }

        // Decrease the total deposited supply value by the redeemed value.
        totalDepositedSupply -= (shares * totalDepositedSupply) / totalSharesSupply;

        // And increase `totalDepositedSupply` with the operation yield.
        totalDepositedSupply += operationYield;

        // Decrease the total shares' supply amount by the redeemed shares.
        totalSharesSupply -= shares;

        // Increase the total shares' supply amount with the operation yield shares.
        totalSharesSupply += operationYieldShares;

        /// Make a redeem operation request into the Pool and get a converted value with the right decimal amount.
        value = moleculaPool.requestRedeem(token, value);

        // Save the redeem operation information.
        redeemRequests[requestId] = RedeemOperationInfo(msg.sender, value, OperationStatus.Pending);

        // Emit the request redeem operation event.
        emit RedeemRequest(requestId, msg.sender, shares, value);

        // Return the value.
        return value;
    }

    /// @inheritdoc ISupplyManager
    function redeem(
        address fromAddress,
        uint256[] memory requestIds
    ) external payable onlyMoleculaPool returns (address token, uint256 redeemedValue) {
        // In the Molecula Pool, we checked that `requestIds` is not empty.
        // Check the status of the first operation.
        if (redeemRequests[requestIds[0]].status != OperationStatus.Pending) {
            revert EBadOperationStatus();
        }

        // Create an array to store the values of the requests.
        uint256[] memory values = new uint256[](requestIds.length);

        // Initialize the first and total values.
        values[0] = redeemRequests[requestIds[0]].value;
        uint256 totalValue = values[0];
        // Get the Agent associated with the first request.
        address agent = redeemRequests[requestIds[0]].agent;
        // Set the status of the first request to `Confirmed`.
        redeemRequests[requestIds[0]].status = OperationStatus.Confirmed;
        // Get the `ERC20` token associated with the Agent.
        token = IAgent(agent).getERC20Token();

        // Loop through the remaining requests.
        for (uint256 i = 1; i < requestIds.length; i++) {
            // Check the status of the operation.
            if (redeemRequests[requestIds[i]].status != OperationStatus.Pending) {
                revert EBadOperationStatus();
            }
            // Check whether the Agent is the same for all requests.
            if (redeemRequests[requestIds[i]].agent != agent) {
                revert EWrongAgent();
            }
            // Add the value of the current request to the values array.
            values[i] = redeemRequests[requestIds[i]].value;
            // Add the value to the total value.
            totalValue += values[i];
            // Set the status of the current request to `Confirmed`.
            redeemRequests[requestIds[i]].status = OperationStatus.Confirmed;
        }

        // Call the `redeem` function on the Agent contract.
        IAgent(agent).redeem{value: msg.value}(fromAddress, requestIds, values, totalValue);

        emit Redeem(requestIds, values);

        // Return the token and total redeemed value to the Molecula Pool.
        return (token, totalValue);
    }

    /**
     * @dev Returns the formatted total supply of the Pool (TVL).
     * @return res Total Pool's supply.
     */
    function totalSupply() public view returns (uint256 res) {
        // Get the Pool's total supply.
        res = moleculaPool.totalSupply();

        // Then reduce it using APY formatter if needed.
        if (totalDepositedSupply < res) {
            res -= totalDepositedSupply;
            res = (res * apyFormatter) / APY_FACTOR;
            res += totalDepositedSupply;
        }
    }

    /**
     * @dev Authorizes a new Agent.
     * @param agent Agent's address.
     * @param auth Boolean flag indicating whether the Agent is authorized.
     */
    function setAgent(address agent, bool auth) external onlyOwner {
        if (agents[agent] == auth) {
            revert EAgentStatusIsAlreadySet();
        }

        if (auth) {
            agents[agent] = true;
            agentsArray.push(agent);
        } else {
            delete agents[agent];
            for (uint256 i = 0; ; ++i) {
                if (agentsArray[i] == agent) {
                    agentsArray[i] = agentsArray[agentsArray.length - 1];
                    // slither-disable-next-line costly-loop
                    agentsArray.pop();
                    break;
                }
            }
        }

        moleculaPool.setAgent(agent, auth);
    }

    /**
     * @inheritdoc ISupplyManager
     */
    function getMoleculaPool() external view returns (address pool) {
        return address(moleculaPool);
    }

    /**
     * @dev Validate a long list of parties.
     * @param agentInfo Agent info with a list of parties.
     * @return total Portion.
     */
    function _validateLongParties(AgentInfo[] memory agentInfo) private view returns (uint256) {
        uint256 totalPortion = 0;
        address[] memory seenAgents = new address[](agentInfo.length);
        uint256 seenCount = 0;
        for (uint256 i = 0; i < agentInfo.length; i++) {
            // Check whether the Agent is valid.
            if (!agents[agentInfo[i].agent]) {
                revert EWrongAgent();
            }
            // Check for duplicate Agents.
            for (uint256 k = 0; k < seenCount; k++) {
                if (seenAgents[k] == agentInfo[i].agent) {
                    revert EDuplicateAgent();
                }
            }
            // Add a seen Agent.
            seenAgents[seenCount] = agentInfo[i].agent;
            seenCount += 1;
            // Get the total portion.
            for (uint256 j = 0; j < agentInfo[i].parties.length; j++) {
                totalPortion += agentInfo[i].parties[j].portion;
            }
        }
        return totalPortion;
    }

    /**
     * @dev Validate parties.
     * @param agentInfo List of parties.
     */
    function _validateParties(AgentInfo[] memory agentInfo) private view {
        // Validate the parties.
        if (agentInfo.length == 0) {
            revert EEmptyParties();
        }
        // Validate the parties.
        uint256 totalPortion = 0;
        if (agentInfo.length < 3) {
            // Check for duplicate Agents.
            if (agentInfo.length == 2 && agentInfo[0].agent == agentInfo[1].agent) {
                revert EDuplicateAgent();
            }
            for (uint256 i = 0; i < agentInfo.length; i++) {
                // Check whether the Agent is valid.
                if (!agents[agentInfo[i].agent]) {
                    revert EWrongAgent();
                }
                // Get the total portion.
                for (uint256 j = 0; j < agentInfo[i].parties.length; j++) {
                    totalPortion += agentInfo[i].parties[j].portion;
                }
            }
        } else {
            // Get the total portion from a "long" parties list.
            totalPortion = _validateLongParties(agentInfo);
        }
        // Check that the total portion is equal to `FULL_PORTION`.
        if (totalPortion != FULL_PORTION) {
            revert EWrongPortion();
        }
    }

    /**
     * @dev Validate APY.
     * @param apy APY.
     */
    function _checkApyFormatter(uint256 apy) internal pure {
        if (apy > APY_FACTOR) {
            revert EInvalidAPY();
        }
    }

    /**
     * @dev Distributes yield.
     * @param agentInfo List of parties.
     * @param newApyFormatter New APY formatter.
     */
    function distributeYield(
        AgentInfo[] memory agentInfo,
        uint256 newApyFormatter
    ) external payable onlyAuthorizedYieldDistributor {
        // Validate the input.
        _checkApyFormatter(newApyFormatter);

        // Validate parties.
        _validateParties(agentInfo);

        // Calculate the extra yield to distribute.
        uint256 realTotalSupply = moleculaPool.totalSupply();
        if (realTotalSupply <= totalDepositedSupply) {
            revert ENoRealYield();
        }
        uint256 realYield = realTotalSupply - totalDepositedSupply;
        uint256 currentYield = (realYield * apyFormatter) / APY_FACTOR;
        uint256 extraYield = realYield - currentYield;
        // Find the amount of shares to mint.
        uint256 newTotalSupply = totalDepositedSupply + currentYield;
        uint256 sharesToMint = (extraYield * totalSharesSupply) / newTotalSupply;

        // Find the amount of shares to distribute by adding the locked yield shares' amount.
        uint256 sharesToDistribute = sharesToMint + lockedYieldShares;

        // Distribute the extra yield to the parties.
        for (uint256 i = 0; i < agentInfo.length; i++) {
            address[] memory users = new address[](agentInfo[i].parties.length);
            uint256[] memory shares = new uint256[](agentInfo[i].parties.length);
            // Calculate shares' value for every user.
            for (uint256 j = 0; j < agentInfo[i].parties.length; j++) {
                Party memory p = agentInfo[i].parties[j];
                users[j] = p.party;
                // slither-disable-next-line divide-before-multiply
                shares[j] = (p.portion * sharesToDistribute) / FULL_PORTION;
            }
            // slither-disable-next-line reentrancy-benign,reentrancy-eth
            IAgent(agentInfo[i].agent).distribute{value: agentInfo[i].ethValue}(users, shares);
        }

        // Distribute an extra yield by:
        // - Increasing the total shares' supply.
        // - Equating the total deposited and real total supply values.
        totalSharesSupply += sharesToMint;
        totalDepositedSupply = realTotalSupply;

        // Reset the locked yield shares' amount.
        lockedYieldShares = 0;

        // Set the new APY formatter.
        apyFormatter = newApyFormatter;

        // Emit an event to log operation.
        emit DistributeYield();
    }

    /**
     * @inheritdoc IOracle
     */
    function getTotalPoolSupply() external view returns (uint256 pool) {
        return totalSupply();
    }

    /**
     * @inheritdoc IOracle
     */
    function getTotalSharesSupply() external view returns (uint256 shares) {
        return totalSharesSupply;
    }

    /**
     * @inheritdoc IOracle
     */
    function getTotalSupply() external view returns (uint256 pool, uint256 shares) {
        pool = totalSupply();
        shares = totalSharesSupply;
    }

    /**
     * @dev Setter for the Authorized Yield Distributor address.
     * @param newAuthorizedYieldDistributor New authorized Yield Distributor address.
     */
    function setAuthorizedYieldDistributor(
        address newAuthorizedYieldDistributor
    ) external onlyOwner checkNotZero(newAuthorizedYieldDistributor) {
        authorizedYieldDistributor = newAuthorizedYieldDistributor;
    }

    /**
     * @dev Setter for the Molecula Pool's address.
     * @param newMoleculaPool New Molecula Pool's address.
     */
    function setMoleculaPool(
        address newMoleculaPool
    ) external onlyOwner checkNotZero(newMoleculaPool) {
        address oldMoleculaPool = address(moleculaPool);
        moleculaPool = IMoleculaPool(newMoleculaPool);
        IMoleculaPool(newMoleculaPool).migrate(address(oldMoleculaPool));
    }

    /// @inheritdoc ISupplyManager
    function getAgents() external view returns (address[] memory) {
        return agentsArray;
    }
}
