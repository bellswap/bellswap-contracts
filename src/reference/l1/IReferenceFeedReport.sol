// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BellTypes} from "./BellTypes.sol";

/// @title IReferenceFeedReport
/// @notice The one ReferenceFeedFactory entry point the L1 relay encodes (SPEC 4.3). Declared here so the L1
/// relay does not depend on the L2 sources; the selector must equal IReferenceFeedFactory.report.
interface IReferenceFeedReport {
    /// @notice Receives one relayed batch on L2; only the aliased relay may call it (SPEC 4.3, 6.4). `seq` is the
    /// ticket's delayed-inbox index, which orders two reads of one L1 block (SPEC 6.6, BELLSWAP-R2-3).
    function report(uint64 l1Block, uint64 seq, uint64 l1Timestamp, BellTypes.Report[] calldata reports) external;
}
