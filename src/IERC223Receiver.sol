// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title  IERC223Receiver
/// @notice Interface that a contract MUST implement to accept ERC-223 token transfers.
///
/// @dev    Source: ERC-223 specification
///         https://eips.ethereum.org/EIPS/eip-223
///
///         Contracts that do not implement this interface will cause any ERC-223
///         `transfer` directed at them to revert, preventing tokens from being
///         accidentally locked.
///
///         The function MUST return the magic value `0x8943ec02`
///         (= bytes4(keccak256("tokenReceived(address,uint256,bytes)")))
///         to signal successful receipt.  Any other return value — or a revert —
///         will cause the originating transfer to fail.
interface IERC223Receiver {
    /// @notice Handle incoming ERC-223 token transfer.
    ///
    /// @param _from  Address of the token sender.
    /// @param _value Amount of tokens transferred (in the token's smallest unit).
    /// @param _data  Arbitrary bytes payload attached to the transfer.
    ///
    /// @return bytes4 Must return `0x8943ec02` on success.
    function tokenReceived(address _from, uint256 _value, bytes calldata _data) external returns (bytes4);
}
