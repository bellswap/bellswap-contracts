// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BellTypes} from "./BellTypes.sol";
import {IBellswapRelay} from "./IBellswapRelay.sol";
import {IOndoPrices} from "./IOndoPrices.sol";
import {IAggregatorV3} from "./IAggregatorV3.sol";
import {IReferenceFeedReport} from "./IReferenceFeedReport.sol";
import {IInboxMinimal, IBridgeMinimal} from "../../vendor/IInboxMinimal.sol";

/// @title BellswapRelay
/// @notice L1 relay of the reference layer (SPEC 4.2, 6.1 to 6.3). Stateless: no storage, no owner, no admin, no
/// fee. Anyone may call every function. The caller chooses the subjects, the L2 target and the ticket gas; the
/// caller cannot choose any price, timestamp or decimals, which are read from the sources in the same transaction.
/// Every validation failure reverts before any ETH moves. The whole msg.value is forwarded to the Inbox, with
/// maxSubmissionCost = msg.value - gasLimit * maxFeePerGas, so overfunding is refunded to refundTo on L2 (SPEC 6.3).
contract BellswapRelay is IBellswapRelay {
    /// @inheritdoc IBellswapRelay
    address public immutable INBOX;
    /// @inheritdoc IBellswapRelay
    address public immutable ONDO_ORACLE;

    uint256 private constant _SOURCE_CALL_GAS = 100_000;
    uint256 private constant _MAX_BATCH = 16;
    uint128 private constant _MIN_PRICE18 = 1e10;
    uint8 private constant _MAX_SOURCE_DECIMALS = 36;
    uint256 private constant _MIN_L2_GAS_BASE = 100_000;
    /// @dev Worst case L2 gas of one report, independent of L2 time: ReferenceFeed.push runs the lazy hold end,
    /// promotion and epoch roll against block.timestamp (SPEC 6.6), so an estimate taken before a promotion falls
    /// due is too low once the ticket executes 435 to 773 s later. Measured cold, one transaction per ticket, the
    /// heaviest report is a late first round at about 166k marginal gas (test/review/c1/regress/TicketGasFloor.t.sol).
    uint256 private constant _MIN_L2_GAS_PER_REPORT = 200_000;

    /// @dev Returndata floors of the two source reads (SPEC 4.2): four words for prices(), five for
    /// latestRoundData(), one for decimals().
    uint256 private constant _PRICES_RETURN_SIZE = 128;
    uint256 private constant _ROUND_RETURN_SIZE = 160;
    uint256 private constant _DECIMALS_RETURN_SIZE = 32;

    /// @param inbox Arbitrum delayed Inbox of the child chain; nonzero and must have code.
    /// @param ondoOracle The kind 1 source (the sanity oracle on this L1, or the Sepolia mock); nonzero.
    /// @dev An inbox without code reverts ZeroAddress, since for this relay it is as absent as address(0).
    constructor(address inbox, address ondoOracle) {
        if (inbox == address(0) || ondoOracle == address(0) || inbox.code.length == 0) revert ZeroAddress();
        INBOX = inbox;
        ONDO_ORACLE = ondoOracle;
    }

    // ------------------------------------------------------------------ constants

    /// @inheritdoc IBellswapRelay
    function SOURCE_CALL_GAS() external pure returns (uint256) {
        return _SOURCE_CALL_GAS;
    }

    /// @inheritdoc IBellswapRelay
    function MAX_BATCH() external pure returns (uint256) {
        return _MAX_BATCH;
    }

    /// @inheritdoc IBellswapRelay
    function MIN_PRICE18() external pure returns (uint128) {
        return _MIN_PRICE18;
    }

    /// @inheritdoc IBellswapRelay
    function MAX_SOURCE_DECIMALS() external pure returns (uint8) {
        return _MAX_SOURCE_DECIMALS;
    }

    /// @inheritdoc IBellswapRelay
    function MIN_L2_GAS_BASE() external pure returns (uint256) {
        return _MIN_L2_GAS_BASE;
    }

    /// @inheritdoc IBellswapRelay
    function MIN_L2_GAS_PER_REPORT() external pure returns (uint256) {
        return _MIN_L2_GAS_PER_REPORT;
    }

    // ------------------------------------------------------------------ pure helpers

    /// @inheritdoc IBellswapRelay
    function minL2Gas(uint256 count) public pure returns (uint256) {
        return _MIN_L2_GAS_BASE + count * _MIN_L2_GAS_PER_REPORT;
    }

    /// @inheritdoc IBellswapRelay
    function feedIdOf(uint8 kind, address source, address subject) external pure returns (bytes32) {
        return BellTypes.feedId(kind, source, subject);
    }

    // ------------------------------------------------------------------ keeper views

    /// @inheritdoc IBellswapRelay
    function observeOndo(address[] calldata tokens) external view returns (BellTypes.Report[] memory) {
        return _observeOndo(tokens);
    }

    /// @inheritdoc IBellswapRelay
    function observeAggregators(address[] calldata aggregators) external view returns (BellTypes.Report[] memory) {
        return _observeAggregators(aggregators);
    }

    /// @inheritdoc IBellswapRelay
    function buildOndo(address[] calldata tokens) external view returns (bytes memory l2Calldata) {
        return _encode(_observeOndo(tokens));
    }

    /// @inheritdoc IBellswapRelay
    function buildAggregators(address[] calldata aggregators) external view returns (bytes memory l2Calldata) {
        return _encode(_observeAggregators(aggregators));
    }

    /// @inheritdoc IBellswapRelay
    /// @dev submissionCost = INBOX.calculateRetryableSubmissionFee(dataLength, l1BaseFee);
    /// totalValue = submissionCost + gasLimit * maxFeePerGas. Reverts on arithmetic overflow.
    function quote(uint256 dataLength, uint256 l1BaseFee, uint256 gasLimit, uint256 maxFeePerGas)
        external
        view
        returns (uint256 submissionCost, uint256 totalValue)
    {
        submissionCost = IInboxMinimal(INBOX).calculateRetryableSubmissionFee(dataLength, l1BaseFee);
        totalValue = submissionCost + gasLimit * maxFeePerGas;
    }

    // ------------------------------------------------------------------ relays

    /// @inheritdoc IBellswapRelay
    function relayOndo(
        address[] calldata tokens,
        address l2Target,
        address refundTo,
        uint256 gasLimit,
        uint256 maxFeePerGas
    ) external payable returns (uint256 ticketId) {
        _checkTicketArgs(tokens.length, l2Target, refundTo, gasLimit);
        BellTypes.Report[] memory reports = _observeOndo(tokens);
        ticketId = _send(BellTypes.KIND_ONDO, reports, l2Target, refundTo, gasLimit, maxFeePerGas);
    }

    /// @inheritdoc IBellswapRelay
    function relayAggregators(
        address[] calldata aggregators,
        address l2Target,
        address refundTo,
        uint256 gasLimit,
        uint256 maxFeePerGas
    ) external payable returns (uint256 ticketId) {
        _checkTicketArgs(aggregators.length, l2Target, refundTo, gasLimit);
        BellTypes.Report[] memory reports = _observeAggregators(aggregators);
        ticketId = _send(BellTypes.KIND_AGGREGATOR, reports, l2Target, refundTo, gasLimit, maxFeePerGas);
    }

    // ------------------------------------------------------------------ internals

    function _checkBatch(uint256 count) private pure {
        if (count == 0) revert EmptyBatch();
        if (count > _MAX_BATCH) revert BatchTooLarge(count);
    }

    function _checkTicketArgs(uint256 count, address l2Target, address refundTo, uint256 gasLimit) private pure {
        _checkBatch(count);
        if (l2Target == address(0) || refundTo == address(0)) revert ZeroAddress();
        uint256 required = minL2Gas(count);
        if (gasLimit < required) revert GasTooLow(required);
    }

    function _observeOndo(address[] calldata tokens) private view returns (BellTypes.Report[] memory reports) {
        _checkBatch(tokens.length);
        address oracle = ONDO_ORACLE;
        bytes32 codehash = oracle.codehash;
        reports = new BellTypes.Report[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) {
            address token = tokens[i];
            if (token == address(0)) revert ZeroAddress();
            (bool ok, uint256 price, uint256 lastUpdated, uint256 maxTimeDelay, uint256 deviationBps,) =
                _read(oracle, abi.encodeCall(IOndoPrices.prices, (token)), _PRICES_RETURN_SIZE);
            // A word that does not fit its ABI type is malformed returndata, treated like a failed read.
            if (!ok || price == 0 || maxTimeDelay > type(uint32).max || deviationBps > type(uint16).max) {
                revert NoPrice(token);
            }
            // The future bound is the spec rule itself (SPEC 4.2); it also bounds lastUpdated to uint64.
            // forge-lint: disable-next-line(block-timestamp)
            if (lastUpdated == 0 || lastUpdated > block.timestamp) revert FutureTimestamp(token);
            if (price < _MIN_PRICE18 || price > type(uint128).max) revert PriceOutOfRange(token);
            // Casts are safe: every word was range checked above (price < 2**128, lastUpdated <= block.timestamp,
            // maxTimeDelay <= type(uint32).max, deviationBps <= type(uint16).max).
            // forge-lint: disable-start(unsafe-typecast)
            reports[i] = BellTypes.Report({
                kind: BellTypes.KIND_ONDO,
                source: oracle,
                subject: token,
                price18: uint128(price),
                observedAt: uint64(lastUpdated),
                maxTimeDelay: uint32(maxTimeDelay),
                deviationBps: uint16(deviationBps),
                rawDecimals: 18,
                sourceCodehash: codehash
            });
            // forge-lint: disable-end(unsafe-typecast)
        }
    }

    function _observeAggregators(address[] calldata aggregators)
        private
        view
        returns (BellTypes.Report[] memory reports)
    {
        _checkBatch(aggregators.length);
        reports = new BellTypes.Report[](aggregators.length);
        for (uint256 i; i < aggregators.length; ++i) {
            address agg = aggregators[i];
            if (agg == address(0)) revert ZeroAddress();
            (bool ok, uint256 dec,,,,) = _read(agg, abi.encodeCall(IAggregatorV3.decimals, ()), _DECIMALS_RETURN_SIZE);
            if (!ok || dec > _MAX_SOURCE_DECIMALS) revert BadDecimals(agg);
            uint256 answerWord;
            uint256 updatedAt;
            (ok,, answerWord,, updatedAt,) =
                _read(agg, abi.encodeCall(IAggregatorV3.latestRoundData, ()), _ROUND_RETURN_SIZE);
            // The answer word is an ABI int256; reinterpreting it is the decode, and a negative answer is rejected.
            // forge-lint: disable-next-line(unsafe-typecast)
            if (!ok || int256(answerWord) <= 0) revert NoPrice(agg);
            // forge-lint: disable-next-line(block-timestamp)
            if (updatedAt == 0 || updatedAt > block.timestamp) revert FutureTimestamp(agg);
            uint256 price18 = _normalise(answerWord, dec, agg);
            if (price18 < _MIN_PRICE18 || price18 > type(uint128).max) revert PriceOutOfRange(agg);
            // Casts are safe: price18 < 2**128, updatedAt <= block.timestamp, dec <= 36, all checked above.
            // forge-lint: disable-start(unsafe-typecast)
            reports[i] = BellTypes.Report({
                kind: BellTypes.KIND_AGGREGATOR,
                source: agg,
                subject: address(0),
                price18: uint128(price18),
                observedAt: uint64(updatedAt),
                maxTimeDelay: 0,
                deviationBps: 0,
                rawDecimals: uint8(dec),
                sourceCodehash: agg.codehash
            });
            // forge-lint: disable-end(unsafe-typecast)
        }
    }

    /// @dev answer > 0 and dec <= 36. Scaling up can only grow the value, so an answer of 2**128 or more is out of
    /// range before the multiplication, which then cannot overflow (2**128 * 1e18 < 2**256).
    function _normalise(uint256 answer, uint256 dec, address agg) private pure returns (uint256) {
        if (dec <= 18) {
            if (answer > type(uint128).max) revert PriceOutOfRange(agg);
            return answer * 10 ** (18 - dec);
        }
        return answer / 10 ** (dec - 18);
    }

    /// @dev Gas capped staticcall that copies at most five words of returndata, so a hostile source can neither
    /// burn the transaction nor inflate memory. ok is false when the call fails or returns fewer than minSize bytes.
    function _read(address target, bytes memory callData, uint256 minSize)
        private
        view
        returns (bool ok, uint256 w0, uint256 w1, uint256 w2, uint256 w3, uint256 w4)
    {
        uint256 gasCap = _SOURCE_CALL_GAS;
        assembly ("memory-safe") {
            let out := mload(0x40)
            let success := staticcall(gasCap, target, add(callData, 0x20), mload(callData), out, 0xa0)
            ok := and(success, iszero(lt(returndatasize(), minSize)))
            w0 := mload(out)
            w1 := mload(add(out, 0x20))
            w2 := mload(add(out, 0x40))
            w3 := mload(add(out, 0x60))
            w4 := mload(add(out, 0x80))
        }
    }

    /// @dev The L2 calldata: ReferenceFeedFactory.report(l1Block, seq, l1Timestamp, reports) (SPEC 6.1 step 6). seq is
    /// the Bridge's delayedMessageCount read before createRetryableTicket enqueues this ticket, so it is the ticket's
    /// delayed-inbox index: authenticated with the rest of the calldata, unique, and increasing in L1 transaction order
    /// also within one L1 block, where l1Block alone cannot order two reads (BELLSWAP-R2-3). The relay stays stateless.
    function _encode(BellTypes.Report[] memory reports) private view returns (bytes memory) {
        // A delayed message count never reaches 2**64, so the cast is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 seq = uint64(IBridgeMinimal(IInboxMinimal(INBOX).bridge()).delayedMessageCount());
        return
            abi.encodeCall(IReferenceFeedReport.report, (uint64(block.number), seq, uint64(block.timestamp), reports));
    }

    function _send(
        uint8 kind,
        BellTypes.Report[] memory reports,
        address l2Target,
        address refundTo,
        uint256 gasLimit,
        uint256 maxFeePerGas
    ) private returns (uint256 ticketId) {
        bytes memory data = _encode(reports);
        uint256 submission = IInboxMinimal(INBOX).calculateRetryableSubmissionFee(data.length, block.basefee);
        if (maxFeePerGas != 0 && gasLimit > type(uint256).max / maxFeePerGas) {
            revert InsufficientValue(type(uint256).max, msg.value);
        }
        uint256 gasBudget = gasLimit * maxFeePerGas;
        if (msg.value < gasBudget || msg.value - gasBudget < submission) {
            uint256 required = gasBudget > type(uint256).max - submission ? type(uint256).max : gasBudget + submission;
            revert InsufficientValue(required, msg.value);
        }
        uint256 maxSubmissionCost = msg.value - gasBudget;
        ticketId = IInboxMinimal(INBOX).createRetryableTicket{value: msg.value}(
            l2Target, 0, maxSubmissionCost, refundTo, refundTo, gasLimit, maxFeePerGas, data
        );
        emit Relayed(ticketId, l2Target, msg.sender, kind, reports.length, keccak256(data), maxSubmissionCost);
        for (uint256 i; i < reports.length; ++i) {
            BellTypes.Report memory r = reports[i];
            emit ReportSent(BellTypes.feedId(r.kind, r.source, r.subject), ticketId, r.price18, r.observedAt);
        }
    }
}
