// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

uint16 constant BASE = 0x100;
uint16 constant UNIT = 0x200;

contract OptionsLZ is Ownable {
    /// @dev Base `lzOptions`.
    bytes public base;

    /// @dev Authorized LayerZero configurator.
    address public authorizedLZConfigurator;

    /// @dev Mapping of `gasLimit`.
    mapping(uint16 => uint256) public gasLimit;

    /// @dev Throws an error if the caller is not the authorized LZ configurator.
    error ENotAuthorizedLZConfigurator();

    /// @dev Modifier to check whether the caller is the authorized LZ configurator.
    modifier onlyAuthorizedLZConfigurator() {
        if (msg.sender != authorizedLZConfigurator) {
            revert ENotAuthorizedLZConfigurator();
        }
        _;
    }

    /**
     * @dev Constructor.
     * @param initialOwner Smart contract owner address.
     * @param authorizedLZConfiguratorAddress Authorized LZ configurator address.
     * @param baseBytes Base bytes.
     */
    constructor(
        address initialOwner,
        address authorizedLZConfiguratorAddress,
        bytes memory baseBytes
    ) Ownable(initialOwner) {
        authorizedLZConfigurator = authorizedLZConfiguratorAddress;
        base = baseBytes;
    }

    /**
     * @dev Sets the base bytes.
     * @param baseBytes Base bytes.
     */
    function setLZOptionsBase(bytes memory baseBytes) public onlyAuthorizedLZConfigurator {
        base = baseBytes;
    }

    /**
     * @dev Sets the gas limit.
     * @param msgType Message type.
     * @param gasLimitBase Gas limit base.
     * @param gasLimitUnit Gas limit unit.
     */
    function setGasLimit(
        uint8 msgType,
        uint256 gasLimitBase,
        uint256 gasLimitUnit
    ) public onlyAuthorizedLZConfigurator {
        gasLimit[BASE | msgType] = gasLimitBase;
        gasLimit[UNIT | msgType] = gasLimitUnit;
    }

    /**
     * @dev Get the gas limit.
     * @param msgType Message type.
     * @param count Unit gas limit count.
     * @return lzOptions LayerZero call options.
     */
    function getLzOptions(
        uint8 msgType,
        uint256 count
    ) public view returns (bytes memory lzOptions) {
        uint256 gasLimitTotal = gasLimit[BASE | msgType] + gasLimit[UNIT | msgType] * count;
        lzOptions = base;
        lzOptions = abi.encodePacked(lzOptions, uint128(gasLimitTotal));
    }

    /**
     * @dev Sets the authorized LZ configurator.
     * @param authorizedLZConfiguratorAddress Authorized LZ configurator address.
     */
    function setAuthorizedLZConfigurator(
        address authorizedLZConfiguratorAddress
    ) external onlyOwner {
        authorizedLZConfigurator = authorizedLZConfiguratorAddress;
    }
}
