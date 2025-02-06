// SPDX-FileCopyrightText: 2025 Molecula <info@molecula.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.22; // Make files compatible between the solutions.

interface IRebaseERC20 {
    /**
     * @dev Transfers the `shares` amount of tokens.
     * @param from Tokens owner's address.
     * @param to Tokens recipient's address.
     * @param shares Shares' amount to transfer.
     */
    event TransferShares(address indexed from, address indexed to, uint256 shares);

    /**
     * @dev Mints the token.
     * @param to The recipient address that will get the minted tokens.
     * @param shares Shares amount to mint.
     */
    function mint(address to, uint256 shares) external;

    /**
     * @dev Burns the token.
     * @param account Account whose tokens are to be burnt.
     * @param shares Shares amount to burn.
     */
    function burn(address account, uint256 shares) external;

    /**
     * @dev Converts assets to shares.
     * @param assets Amount of assets to convert.
     * @return shares Converted amount of shares.
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Converts shares to assets.
     * @param shares Amount of shares to convert.
     * @return assets Converted amount of assets.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Returns the user's shares.
     * @param user User whose shares are to be returned.
     * @return shares User's shares.
     */
    function sharesOf(address user) external view returns (uint256 shares);
}
