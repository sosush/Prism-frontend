// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice ERC-5192 Minimal Soulbound NFTs.
/// @dev https://eips.ethereum.org/EIPS/eip-5192
interface IERC5192 {
    /// @notice Emitted when the locking status is changed to locked.
    event Locked(uint256 tokenId);

    /// @notice Emitted when the locking status is changed to unlocked.
    event Unlocked(uint256 tokenId);

    /// @notice Returns the locking status of an Soulbound Token.
    function locked(uint256 tokenId) external view returns (bool);
}
