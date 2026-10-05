// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IOndoPrices
/// @notice Getter ABI of the L1 sanity check oracle, written from the ABI (SPEC 4.1); no source code copied.
/// Price is USD with 18 decimals; an unknown token returns zeros.
interface IOndoPrices {
    /// @notice Latest posted price of `token` with its time, validity window and allowed deviation.
    function prices(address token)
        external
        view
        returns (uint256 price, uint64 lastUpdated, uint32 maxTimeDelay, uint16 allowedDeviationBps);
}
