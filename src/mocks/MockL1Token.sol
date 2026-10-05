// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockL1Token
/// @notice Test fixture (SPEC 4.9): a plain 18-decimal ERC-20 that serves as a price subject of the Sepolia
/// MockSanityOracle. Own MIT code. Name "Test Asset <label>", symbol "T<label>" (label A, B or C on Sepolia).
/// Open mint, test only, never mainnet.
contract MockL1Token is ERC20 {
    /// @param label One-letter label: "A" gives "Test Asset A" and "TA".
    constructor(string memory label) ERC20(string.concat("Test Asset ", label), string.concat("T", label)) {}

    /// @notice Anyone may mint; test only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
