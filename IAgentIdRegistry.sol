// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface for the SPACE ID Agent ID registry on BNB Chain
///         (0x60b9262456de011f7d15a54cdd8c48baaa8b022f, "SPACE ID Agent ID", symbol AI).
/// @dev Interface verified against the live contract's published ABI:
///      - balanceOf(address)  -> number of Agent IDs held (0 or 1; one per user, non-transferable)
///      - handleOf(address)   -> the holder's handle, e.g. "bool01" ("" for non-holders)
///      - ownerOf(uint256)    -> owner of a tokenId, where tokenId == uint256(keccak256(bytes(handle)))
///      The tokenId derivation was confirmed on-chain: ownerOf(keccak256("bool01"))
///      returns the address whose handleOf() is "bool01".
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function handleOf(address owner) external view returns (string memory);
}
