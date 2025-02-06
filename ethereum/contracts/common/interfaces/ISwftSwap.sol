// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @notice swftswap
interface ISwftSwap {
    /// @notice Execute transactions. 从转入的币中扣除手续费。
    /// @param fromToken token's address. 源币的合约地址
    /// @param toToken 目标币的类型，比如'usdt(matic)'
    /// @param destination 目标币的收币地址
    /// @param fromAmount 原币的数量
    /// @param minReturnAmount 用户期望的目标币的最小接收数量
    function swap(
        address fromToken,
        string memory toToken,
        string memory destination,
        uint256 fromAmount,
        uint256 minReturnAmount
    ) external;
}
