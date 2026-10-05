// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IInboxMinimal
/// @notice Own minimal interface to the Arbitrum Nitro delayed Inbox, written from SPEC 4.1 and 6.2.
/// It is not copied from nitro-contracts, which is BUSL-1.1 (SPEC 4.1, 11.2).
/// Selector of createRetryableTicket: 0x679b6ded (SPEC 4.1).
/// Delayed Inbox on Ethereum (parent of 4663): 0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D.
/// Delayed Inbox on Sepolia (parent of 46630): 0xF2939afA86F6f933A3CE17fCAB007907B6b0B7a4 (SPEC 3.1).
interface IInboxMinimal {
    /// @notice Creates a retryable ticket that calls `to` on L2 with `data`.
    /// The L2 sender is the aliased L1 caller (SPEC 6.4). Excess submission cost and unused gas are
    /// refunded to `excessFeeRefundAddress`; `callValueRefundAddress` is the ticket beneficiary and
    /// may cancel an unredeemed ticket (SPEC 6.3).
    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata data
    ) external payable returns (uint256);

    /// @notice Submission fee for a retryable carrying `dataLength` bytes at L1 `baseFee`.
    /// Formula (1400 + 6 * dataLength) * baseFee (SPEC 6.2). Callers pass block.basefee, never 0.
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee) external view returns (uint256);

    /// @notice The Bridge this Inbox enqueues its delayed messages into (Nitro AbsInbox.bridge()).
    function bridge() external view returns (address);
}

/// @title IBridgeMinimal
/// @notice Own minimal interface to the Arbitrum Nitro Bridge (SPEC 4.1, 6.1 step 6).
interface IBridgeMinimal {
    /// @notice Number of delayed messages enqueued so far, which is the index the next delayed message gets. Every
    /// createRetryableTicket enqueues one message, so the value read just before it is that ticket's index: unique and
    /// increasing in L1 transaction order, also within one L1 block.
    function delayedMessageCount() external view returns (uint256);
}
