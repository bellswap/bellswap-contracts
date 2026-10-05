// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IAggregatorV3} from "../reference/l1/IAggregatorV3.sol";

/// @title IMockL1Aggregator
/// @notice Test fixture interface (SPEC 4.9): an AggregatorV3 whose answer and decimals anyone can set.
interface IMockL1Aggregator is IAggregatorV3 {
    /// @notice Starts a new round with `answer` observed at `updatedAt` (startedAt = updatedAt).
    function setAnswer(int256 answer, uint256 updatedAt) external;
    /// @notice Changes decimals(), to test the decimals pin on L2.
    function setDecimals(uint8 decimals) external;
}

/// @title MockAggregatorV3
/// @notice Own MIT open AggregatorV3 mock for unit tests and Sepolia (SPEC 4.9, 6.7). Anyone may set the answer
/// and decimals: test only, never mainnet. Round ids count from 1; answeredInRound equals roundId.
/// latestRoundData returns zeros before the first setAnswer; getRoundData of an unknown round returns zeros.
contract MockAggregatorV3 is IMockL1Aggregator {
    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    uint8 private _decimals;
    uint80 private _latestRound;
    string private _description;
    mapping(uint80 roundId => Round) private _rounds;

    /// @param decimals_ Initial decimals().
    /// @param description_ description() string.
    constructor(uint8 decimals_, string memory description_) {
        _decimals = decimals_;
        _description = description_;
    }

    /// @inheritdoc IAggregatorV3
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IAggregatorV3
    function description() external view returns (string memory) {
        return _description;
    }

    /// @inheritdoc IAggregatorV3
    function version() external pure returns (uint256) {
        return 1;
    }

    /// @inheritdoc IAggregatorV3
    function getRoundData(uint80 roundId) external view returns (uint80, int256, uint256, uint256, uint80) {
        Round memory r = _rounds[roundId];
        if (r.updatedAt == 0 && r.answer == 0) return (roundId, 0, 0, 0, 0);
        return (roundId, r.answer, r.updatedAt, r.updatedAt, roundId);
    }

    /// @inheritdoc IAggregatorV3
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        uint80 id = _latestRound;
        Round memory r = _rounds[id];
        return (id, r.answer, r.updatedAt, r.updatedAt, id);
    }

    /// @inheritdoc IMockL1Aggregator
    function setAnswer(int256 answer, uint256 updatedAt) external {
        uint80 id = _latestRound + 1;
        _latestRound = id;
        _rounds[id] = Round(answer, updatedAt);
    }

    /// @inheritdoc IMockL1Aggregator
    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }
}

/// @title MockL1Aggregator
/// @notice The SPEC 4.9 name of the same fixture.
contract MockL1Aggregator is MockAggregatorV3 {
    /// @param decimals_ Initial decimals().
    /// @param description_ description() string.
    constructor(uint8 decimals_, string memory description_) MockAggregatorV3(decimals_, description_) {}
}
