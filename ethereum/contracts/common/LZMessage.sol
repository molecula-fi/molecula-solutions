// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22;

import "./LZMsgTypes.sol";

contract LZMessage is LZMsgTypes {
    /**
     * @dev Custom error for unknown message types.
     */
    error ELzUnknownMessage();

    /**
     * @dev Encodes a request deposit message.
     * @param requestId Request ID.
     * @param value The value of the request.
     * @return message Encoded message.
     */
    function lzEncodeRequestDepositMessage(
        uint256 requestId,
        uint256 value
    ) public pure returns (bytes memory message) {
        return abi.encodePacked(REQUEST_DEPOSIT, requestId, value);
    }

    /**
     * @dev Decodes a request deposit message.
     * @param message Encoded message.
     * @return requestId Decoded request ID.
     * @return value Decoded value.
     */
    function lzDecodeRequestDepositMessage(
        bytes calldata message
    ) public pure returns (uint256 requestId, uint256 value) {
        return abi.decode(message, (uint256, uint256));
    }

    /**
     * @dev Generates a default request deposit message.
     * @return message Default encoded message.
     */
    function lzDefaultRequestDepositMessage() public pure returns (bytes memory message) {
        return lzEncodeRequestDepositMessage(1, 1);
    }

    /**
     * @dev Encodes a deposit confirmation message.
     * @param requestId Request ID.
     * @param shares Number of shares.
     * @return message Encoded message.
     */
    function lzEncodeConfirmDepositMessage(
        uint256 requestId,
        uint256 shares
    ) public pure returns (bytes memory message) {
        return abi.encodePacked(CONFIRM_DEPOSIT, requestId, shares);
    }

    /**
     * @dev Decodes a deposit confirmation message.
     * @param message Encoded message.
     * @return requestId Decoded request ID.
     * @return shares Decoded shares.
     */
    function lzDecodeConfirmDepositMessage(
        bytes calldata message
    ) public pure returns (uint256 requestId, uint256 shares) {
        return abi.decode(message, (uint256, uint256));
    }

    /**
     * @dev Generates a default deposit confirmation message.
     * @return message Default encoded message.
     */
    function lzDefaultConfirmDepositMessage() public pure returns (bytes memory message) {
        return lzEncodeConfirmDepositMessage(2, 2);
    }

    /**
     * @dev Encodes a deposit confirmation message and update the oracle.
     * @param requestId Request ID.
     * @param shares Number of shares.
     * @param totalValue Total value.
     * @param totalShares Total number of shares.
     * @return message Encoded message.
     */
    function lzEncodeConfirmDepositMessageAndUpdateOracle(
        uint256 requestId,
        uint256 shares,
        uint256 totalValue,
        uint256 totalShares
    ) public pure returns (bytes memory message) {
        return
            abi.encodePacked(
                CONFIRM_DEPOSIT_AND_UPDATE_ORACLE,
                requestId,
                shares,
                totalValue,
                totalShares
            );
    }

    /**
     * @dev Decodes a deposit confirmation message and update the oracle.
     * @param message Encoded message.
     * @return requestId Decoded request ID.
     * @return shares Decoded shares.
     * @return totalValue Decoded total value.
     * @return totalShares Decoded total shares.
     */
    function lzDecodeConfirmDepositMessageAndUpdateOracle(
        bytes calldata message
    )
        public
        pure
        returns (uint256 requestId, uint256 shares, uint256 totalValue, uint256 totalShares)
    {
        return abi.decode(message, (uint256, uint256, uint256, uint256));
    }

    /**
     * @dev Generates a default deposit confirmation message and update the oracle.
     * @return message Default encoded message.
     */
    function lzDefaultConfirmDepositMessageAndUpdateOracle()
        public
        pure
        returns (bytes memory message)
    {
        return lzEncodeConfirmDepositMessageAndUpdateOracle(1, 2, 3, 4);
    }

    /**
     * @dev Encodes a request redeem operation message.
     * @param requestId Request ID.
     * @param shares Number of shares.
     * @return message Encoded message.
     */
    function lzEncodeRequestRedeemMessage(
        uint256 requestId,
        uint256 shares
    ) public pure returns (bytes memory message) {
        return abi.encodePacked(REQUEST_REDEEM, requestId, shares);
    }

    /**
     * @dev Encodes a distribute yield message.
     * @param users The addresses of the users.
     * @param shares Number of shares.
     * @return message Encoded message.
     */
    function lzEncodeDistributeYieldMessage(
        address[] memory users,
        uint256[] memory shares
    ) public pure returns (bytes memory message) {
        message = abi.encodePacked(DISTRIBUTE_YIELD);
        for (uint256 i = 0; i < users.length; i++) {
            message = abi.encodePacked(message, bytes20(users[i]));
        }
        for (uint256 i = 0; i < shares.length; i++) {
            message = abi.encodePacked(message, shares[i]);
        }
    }

    /**
     * @dev Decodes a request redeem operation message.
     * @param message Encoded message.
     * @return requestId Decoded request ID.
     * @return shares Decoded shares.
     */
    function lzDecodeRequestRedeemMessage(
        bytes memory message
    ) public pure returns (uint256 requestId, uint256 shares) {
        return abi.decode(message, (uint256, uint256));
    }

    /**
     * @dev Generates a default request redeem operation message.
     * @return message Default encoded message.
     */
    function lzDefaultRequestRedeemMessage() public pure returns (bytes memory message) {
        return lzEncodeRequestRedeemMessage(3, 3);
    }

    /**
     * @dev Encodes a redeem operation confirmation message.
     * @param requestIds The IDs of the requests.
     * @param values The values of the requests.
     * @return message Encoded message.
     */
    function lzEncodeConfirmRedeemMessage(
        uint256[] memory requestIds,
        uint256[] memory values
    ) public pure returns (bytes memory message) {
        // slither-disable-next-line encode-packed-collision
        return abi.encodePacked(CONFIRM_REDEEM, requestIds, values);
    }

    /**
     * @dev Decodes a yield distribution message.
     * @param message Encoded message.
     * @return users Addresses of the users.
     * @return shares Number of shares.
     */
    function lzDecodeDistributeYieldMessage(
        bytes memory message
    ) public pure returns (address[] memory users, uint256[] memory shares) {
        // Calculate the number of uint256 elements in the message.
        // slither-disable-next-line divide-before-multiply
        uint256 arrayLength = message.length / 52;

        // Decode users.
        users = new address[](arrayLength);
        for (uint256 i = 0; i < arrayLength; i++) {
            uint256 offset = i * 20;
            address element;
            // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
            assembly {
                element := mload(add(message, add(20, offset)))
            }
            users[i] = element;
        }

        // Decode shares.
        shares = new uint256[](arrayLength);
        uint256 constOffset = arrayLength * 20;
        for (uint256 i = 0; i < arrayLength; i++) {
            uint256 offset = constOffset + i * 32;
            bytes32 element;
            // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
            assembly {
                element := mload(add(message, add(32, offset)))
            }
            shares[i] = uint256(element);
        }
    }

    /**
     * @dev Decodes a redeem operation confirmation message.
     * @param message Encoded message.
     * @return requestIds Decoded request IDs.
     * @return values Decoded values.
     */
    function lzDecodeConfirmRedeemMessage(
        bytes memory message
    ) public pure returns (uint256[] memory requestIds, uint256[] memory values) {
        // Calculate the number of uint256 elements in the message.
        // slither-disable-next-line divide-before-multiply
        uint256 arrayLength = message.length / 64;

        // Decode request IDs.
        requestIds = new uint256[](arrayLength);
        for (uint256 i = 0; i < arrayLength; i++) {
            uint256 offset = i * 32;
            bytes32 element;
            // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
            assembly {
                element := mload(add(message, add(32, offset)))
            }
            requestIds[i] = uint256(element);
        }

        // Decode values.
        values = new uint256[](arrayLength);
        uint256 constOffset = arrayLength * 32;
        for (uint256 i = 0; i < arrayLength; i++) {
            uint256 offset = constOffset + i * 32;
            bytes32 element;
            // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
            assembly {
                element := mload(add(message, add(32, offset)))
            }
            values[i] = uint256(element);
        }
    }

    /**
     * @dev Generates a default redeem operation confirmation message.
     * @param count Number of elements.
     * @return message Default encoded message.
     */
    function lzDefaultDistributeYieldMessage(
        uint256 count
    ) public pure returns (bytes memory message) {
        address[] memory users = new address[](count);
        uint256[] memory shares = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = address(1);
            shares[i] = i;
        }
        return lzEncodeDistributeYieldMessage(users, shares);
    }

    /**
     * @dev Generates a default redeem operation confirmation message.
     * @param idsCount The number of request IDs.
     * @return message Default encoded message.
     */
    function lzDefaultConfirmRedeemMessage(
        uint256 idsCount
    ) public pure returns (bytes memory message) {
        uint256[] memory requestId = new uint256[](idsCount);
        uint256[] memory values = new uint256[](idsCount);
        for (uint256 i = 0; i < idsCount; i++) {
            requestId[i] = i;
            values[i] = i;
        }
        return lzEncodeConfirmRedeemMessage(requestId, values);
    }

    /**
     * @dev Encodes a distribute yield message and update the oracle.
     * @param users The addresses of the users.
     * @param shares Number of shares.
     * @param totalValue Total value.
     * @param totalShares Total shares.
     * @return message Encoded message.
     */
    function lzEncodeDistributeYieldMessageAndUpdateOracle(
        address[] memory users,
        uint256[] memory shares,
        uint256 totalValue,
        uint256 totalShares
    ) public pure returns (bytes memory message) {
        message = abi.encodePacked(DISTRIBUTE_YIELD_AND_UPDATE_ORACLE);
        message = abi.encodePacked(message, totalValue, totalShares);
        for (uint256 i = 0; i < users.length; i++) {
            message = abi.encodePacked(message, bytes20(users[i]));
        }
        for (uint256 i = 0; i < shares.length; i++) {
            message = abi.encodePacked(message, shares[i]);
        }
    }

    /**
     * @dev Decodes a yield distribution message and update the oracle.
     * @param message Encoded message.
     * @return users Addresses of the users.
     * @return shares Number of shares.
     * @return totalValue Total value.
     * @return totalShares Total shares.
     */
    function lzDecodeDistributeYieldMessageAndUpdateOracle(
        bytes memory message
    )
        public
        pure
        returns (
            address[] memory users,
            uint256[] memory shares,
            uint256 totalValue,
            uint256 totalShares
        )
    {
        // Decode `totalValue` and `totalShares` stored at the beginning of the message.
        // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
        assembly {
            totalValue := mload(add(message, 32)) // Load `totalValue` from the beginning.
            totalShares := mload(add(message, 64)) // Load `totalShares` after `totalValue`.
        }

        // Calculate the number of uint256 elements in the message.
        // slither-disable-next-line divide-before-multiply
        uint256 arrayLength = (message.length - 64) / 52;

        // Decode users.
        users = new address[](arrayLength);
        for (uint256 i = 0; i < arrayLength; i++) {
            uint256 offset = 64 + i * 20;
            address element;
            // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
            assembly {
                element := mload(add(message, add(20, offset)))
            }
            users[i] = element;
        }

        // Decode shares.
        shares = new uint256[](arrayLength);
        uint256 constOffset = 64 + arrayLength * 20;
        for (uint256 i = 0; i < arrayLength; i++) {
            uint256 offset = constOffset + i * 32;
            bytes32 element;
            // slither-disable-next-line assembly, solhint-disable-next-line no-inline-assembly
            assembly {
                element := mload(add(message, add(32, offset)))
            }
            shares[i] = uint256(element);
        }
    }

    /**
     * @dev Generates a default redeem operation confirmation message and update the oracle.
     * @param count Number of elements.
     * @return message Default encoded message.
     */
    function lzDefaultDistributeYieldMessageAndUpdateOracle(
        uint256 count
    ) public pure returns (bytes memory message) {
        address[] memory users = new address[](count);
        uint256[] memory shares = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            users[i] = address(1);
            shares[i] = i;
        }
        return lzEncodeDistributeYieldMessageAndUpdateOracle(users, shares, 1, 2);
    }

    /**
     * @dev Encodes an oracle update message.
     * @param totalValue Total value.
     * @param totalShares Total shares.
     * @return message Encoded message.
     */
    function lzEncodeUpdateOracle(
        uint256 totalValue,
        uint256 totalShares
    ) public pure returns (bytes memory message) {
        return abi.encodePacked(UPDATE_ORACLE, totalValue, totalShares);
    }

    /**
     * @dev Decodes an oracle update message.
     * @param message Encoded message.
     * @return totalValue Total value.
     * @return totalShares Total shares.
     */
    function lzDecodeUpdateOracle(
        bytes calldata message
    ) public pure returns (uint256 totalValue, uint256 totalShares) {
        return abi.decode(message, (uint256, uint256));
    }

    /**
     * @dev Generates a default oracle update message.
     * @return message Default encoded message.
     */
    function lzDefaultUpdateOracleMessage() public pure returns (bytes memory message) {
        return lzEncodeUpdateOracle(1, 2);
    }
}
