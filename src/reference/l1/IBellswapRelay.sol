// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BellTypes} from "./BellTypes.sol";

/// @title IBellswapRelay
/// @notice L1 relay of the reference layer (SPEC 4.2). Reads named sources in one transaction, validates them and
/// sends `ReferenceFeedFactory.report(l1Block, seq, l1Timestamp, reports)` to L2 as one retryable ticket.
interface IBellswapRelay {
    error EmptyBatch();
    error BatchTooLarge(uint256 count);
    error ZeroAddress();
    error NoPrice(address subject); // call failed, short returndata, price == 0 or answer <= 0
    error FutureTimestamp(address subject); // observedAt == 0 or observedAt > block.timestamp
    error PriceOutOfRange(address subject); // price18 < MIN_PRICE18 or >= 2**128
    error BadDecimals(address subject); // aggregator decimals unreadable or > MAX_SOURCE_DECIMALS
    error GasTooLow(uint256 required); // gasLimit < minL2Gas(count)
    error InsufficientValue(uint256 required, uint256 provided);

    event Relayed(
        uint256 indexed ticketId,
        address indexed l2Target,
        address indexed caller,
        uint8 kind,
        uint256 count,
        bytes32 payloadHash,
        uint256 submissionCost
    );
    event ReportSent(bytes32 indexed feedId, uint256 indexed ticketId, uint128 price18, uint64 observedAt);

    /// @notice Arbitrum delayed Inbox of the child chain (immutable).
    function INBOX() external view returns (address);
    /// @notice The kind 1 source, the sanity oracle on this L1 (immutable).
    function ONDO_ORACLE() external view returns (address);
    /// @notice Gas cap of every source staticcall: 100_000.
    function SOURCE_CALL_GAS() external pure returns (uint256);
    /// @notice Largest batch: 16.
    function MAX_BATCH() external pure returns (uint256);
    /// @notice Smallest accepted price18: 1e10, so the 8 decimal answer is at least 1.
    function MIN_PRICE18() external pure returns (uint128);
    /// @notice Largest accepted aggregator decimals: 36.
    function MAX_SOURCE_DECIMALS() external pure returns (uint8);
    /// @notice Fixed part of the L2 gas floor: 100_000.
    function MIN_L2_GAS_BASE() external pure returns (uint256);
    /// @notice Per report part of the L2 gas floor: 200_000. It covers the worst case push of one report whatever
    /// the L2 time of execution (first round, or a lazy hold end, promotion and epoch roll plus a new pending round),
    /// because a gas estimate taken before the ticket executes cannot see a promotion that falls due in flight.
    function MIN_L2_GAS_PER_REPORT() external pure returns (uint256);

    /// @notice L2 gas floor for `count` reports: MIN_L2_GAS_BASE + count * MIN_L2_GAS_PER_REPORT.
    function minL2Gas(uint256 count) external pure returns (uint256);
    /// @notice keccak256(abi.encode(kind, source, subject)), the same id the L2 factory uses.
    function feedIdOf(uint8 kind, address source, address subject) external pure returns (bytes32);

    /// @notice The reports relayOndo would send now for `tokens`; reverts as relayOndo would.
    function observeOndo(address[] calldata tokens) external view returns (BellTypes.Report[] memory);
    /// @notice The reports relayAggregators would send now for `aggregators`; reverts as relayAggregators would.
    function observeAggregators(address[] calldata aggregators) external view returns (BellTypes.Report[] memory);
    /// @notice The exact L2 calldata relayOndo would send in this block.
    function buildOndo(address[] calldata tokens) external view returns (bytes memory l2Calldata);
    /// @notice The exact L2 calldata relayAggregators would send in this block.
    function buildAggregators(address[] calldata aggregators) external view returns (bytes memory l2Calldata);

    /// @notice Submission fee and total msg.value for a ticket. l1BaseFee must be passed explicitly: eth_call
    /// runs with basefee 0.
    function quote(uint256 dataLength, uint256 l1BaseFee, uint256 gasLimit, uint256 maxFeePerGas)
        external
        view
        returns (uint256 submissionCost, uint256 totalValue);

    /// @notice Reads ONDO_ORACLE.prices(token) for each token with SOURCE_CALL_GAS, validates, and sends one
    /// retryable ticket with maxSubmissionCost = msg.value - gasLimit * maxFeePerGas (SPEC 6.2, 6.3).
    function relayOndo(
        address[] calldata tokens,
        address l2Target,
        address refundTo,
        uint256 gasLimit,
        uint256 maxFeePerGas
    ) external payable returns (uint256 ticketId);

    /// @notice Same for L1 AggregatorV3 feeds: reads decimals() and latestRoundData(), normalises to 18 decimals.
    function relayAggregators(
        address[] calldata aggregators,
        address l2Target,
        address refundTo,
        uint256 gasLimit,
        uint256 maxFeePerGas
    ) external payable returns (uint256 ticketId);
}
