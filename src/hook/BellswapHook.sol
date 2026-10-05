// SPDX-License-Identifier: MIT
// Derived from Bellguard (MIT), Copyright (c) 2026 Bellguard contributors,
// <workspace>/bellguard/bellguard/src/BellHook.sol at commit 3ab656b. Reused per SPEC 7.1:
// the beforeSwap return shape (:176-184), the gap math (:330-335), the feed read (:317-326), the
// sqrtPriceX96 to price conversion (:357-362) and the decimals read (:399-404), each changed as
// SPEC 7.1 states. Admission, BellConfig, the float guard and reserve tracking are dropped.
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {BaseHook} from "./BaseHook.sol";
import {IBellswapHook} from "./IBellswapHook.sol";

/// @title BellswapHook
/// @notice Immutable Uniswap v4 hook with a per-pool fee curve anchored to a reference feed.
///         Pools exist only through createPool (generic, caller-chosen curve) and
///         createSyntheticPool (a synthetic against USDG with the canonical curve). While every feed
///         is fresh the fee is baseFee plus a gap fee on the gap between the pool price and the
///         anchor beyond bandBps; the gap fee applies only to trades moving away from the anchor in
///         Directional mode. The fee is the larger of the fees at the pre-swap price and at the pool
///         price before the block's first swap, so crossing the anchor within a block does not avoid
///         it. A stale, broken or unreadable feed, or a synthetic that is no longer
///         Live, yields maxFee in both directions (fail closed).
/// @dev No owner, no admin function, no proxy, no delegated call, no self-destruct, no fee path: every
///      fee goes to LPs through PoolManager. Every external read of a feed or token is a staticcall
///      capped at FEED_CALL_GAS that copies at most 160 bytes of return data.
contract BellswapHook is BaseHook, IBellswapHook {
    using PoolIdLibrary for PoolKey;

    uint24 private constant MIN_FEE_ = 100;
    uint24 private constant MAX_FEE_ = 100_000;
    uint256 private constant FEED_CALL_GAS_ = 100_000;
    uint16 private constant INIT_BAND_FLOOR_BPS_ = 1_000;

    // SPEC 5.2 bounds of PoolConfig.
    uint24 private constant BASE_FEE_CAP = 10_000;
    uint16 private constant BAND_CAP = 2_000;
    uint16 private constant SLOPE_CAP = 1_000;
    uint32 private constant STALE_MIN = 3_600;
    uint32 private constant STALE_MAX = 604_800;

    // Canonical synthetic curve (SPEC 5.2).
    uint24 private constant CANON_BASE_FEE = 3_000;
    uint24 private constant CANON_MAX_FEE = 30_000;
    uint16 private constant CANON_BAND = 1_000;
    uint16 private constant CANON_SLOPE = 100;
    uint32 private constant CANON_STALE = 194_400;

    uint256 private constant BPS = 10_000;
    /// @dev Scale of every price the hook computes: whole quote tokens per whole base token, times 1e18.
    uint256 private constant SCALE = 1e18;
    /// @dev Largest accepted feed answer. Larger answers count as Broken so the USD normalisation
    ///      below cannot overflow (SPEC H3: a huge answer never reverts).
    uint256 private constant MAX_ANSWER = type(uint128).max;
    /// @dev Saturation point of gapBps (SPEC 7.3 "saturating").
    uint256 private constant GAP_SATURATION = 1e40;
    /// @dev PoolManager storage slot of `mapping(PoolId => Pool.State) pools` in v4-core v4.0.0
    ///      (StateLibrary.POOLS_SLOT, lib/v4-core/src/libraries/StateLibrary.sol:11).
    bytes32 private constant POOLS_SLOT = bytes32(uint256(6));

    bytes4 private constant SEL_LATEST_ROUND_DATA = bytes4(keccak256("latestRoundData()"));
    bytes4 private constant SEL_DECIMALS = bytes4(keccak256("decimals()"));
    bytes4 private constant SEL_REFERENCE_FEED = bytes4(keccak256("referenceFeed()"));
    bytes4 private constant SEL_SETTLEMENT_STATE = bytes4(keccak256("settlementState()"));

    /// @inheritdoc IBellswapHook
    address public immutable USDG;

    mapping(PoolId => PoolInfo) private _poolInfo;
    /// @dev Base currency of each pool, written once with PoolInfo; read for settlementState().
    mapping(PoolId => address) private _baseOf;
    PoolId[] private _pools;

    /// @dev Pool price before the first swap of a block, written by beforeSwap. The fee is the larger of
    ///      the fees at the pre-swap price and at this price (or at the swap's price limit when that limit
    ///      stops the swap before this price), so a toward-first round trip within one block cannot turn a
    ///      deep away trade into a toward trade.
    struct BlockStart {
        uint64 blockNumber;
        uint160 sqrtPriceX96;
    }

    mapping(PoolId => BlockStart) private _blockStart;

    /// @param manager The Uniswap v4 PoolManager (0x8366a39CC670B4001A1121B8F6A443A643e40951 on 4663).
    /// @param usdg The quote currency of every synthetic pool.
    constructor(IPoolManager manager, address usdg) BaseHook(manager) {
        USDG = usdg;
    }

    // ------------------------------------------------------------------------------------------
    // Constants and immutables
    // ------------------------------------------------------------------------------------------

    /// @inheritdoc IBellswapHook
    function POOL_MANAGER() external view returns (IPoolManager) {
        return poolManager;
    }

    /// @inheritdoc IBellswapHook
    function MIN_FEE() external pure returns (uint24) {
        return MIN_FEE_;
    }

    /// @inheritdoc IBellswapHook
    function MAX_FEE() external pure returns (uint24) {
        return MAX_FEE_;
    }

    /// @inheritdoc IBellswapHook
    function FEED_CALL_GAS() external pure returns (uint256) {
        return FEED_CALL_GAS_;
    }

    /// @inheritdoc IBellswapHook
    function INIT_BAND_FLOOR_BPS() external pure returns (uint16) {
        return INIT_BAND_FLOOR_BPS_;
    }

    /// @notice Hook permissions: beforeInitialize (always reverts) and beforeSwap (fee override) only.
    ///         No return-delta flag, no liquidity or donate callbacks.
    /// @return The permissions struct validated against the hook address at construction.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ------------------------------------------------------------------------------------------
    // Pool creation (SPEC 7.2)
    // ------------------------------------------------------------------------------------------

    /// @inheritdoc IBellswapHook
    function createPool(PoolKey calldata key, PoolConfig calldata cfg, uint160 sqrtPriceX96)
        external
        returns (PoolId id, int24 tick)
    {
        _checkKey(key);
        if (_declaresReference(Currency.unwrap(key.currency0)) || _declaresReference(Currency.unwrap(key.currency1))) {
            revert UseSyntheticPool();
        }
        return _create(key, cfg, sqrtPriceX96, false);
    }

    /// @inheritdoc IBellswapHook
    function createSyntheticPool(address synth, int24 tickSpacing, uint160 sqrtPriceX96)
        external
        returns (PoolId id, int24 tick)
    {
        (bool ok, uint256[5] memory w) = _read(synth, SEL_REFERENCE_FEED, 32);
        if (!ok || w[0] == 0 || w[0] > type(uint160).max) revert NotReferenced();
        address feed = address(uint160(w[0]));

        address usdg = USDG;
        bool synthIs0 = synth < usdg;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(synthIs0 ? synth : usdg),
            currency1: Currency.wrap(synthIs0 ? usdg : synth),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(this))
        });
        _checkKey(key);
        return _create(key, _canonical(feed, synthIs0), sqrtPriceX96, true);
    }

    /// @inheritdoc IBellswapHook
    function canonicalConfig(address feed, bool baseIsCurrency0) external pure returns (PoolConfig memory) {
        return _canonical(feed, baseIsCurrency0);
    }

    /// @dev Step 1 of SPEC 7.2: the key names this hook, the dynamic fee flag and no native currency.
    function _checkKey(PoolKey memory key) private view {
        if (address(key.hooks) != address(this)) revert WrongHook();
        if (key.fee != LPFeeLibrary.DYNAMIC_FEE_FLAG) revert NotDynamicFee();
        if (Currency.unwrap(key.currency0) == address(0) || Currency.unwrap(key.currency1) == address(0)) {
            revert NativeNotSupported();
        }
    }

    /// @dev Steps 3 to 7 of SPEC 7.2, shared by both creation paths.
    function _create(PoolKey memory key, PoolConfig memory cfg, uint160 sqrtPriceX96, bool synthetic)
        private
        returns (PoolId id, int24 tick)
    {
        _checkConfig(cfg, key.tickSpacing);
        (PoolInfo memory info, address base) = _buildInfo(key, cfg, synthetic);
        _checkInitPrice(info, sqrtPriceX96);

        // Step 6: record once, then step 7. A key that already exists makes initialize revert, which
        // reverts this whole call, so PoolInfo is written exactly once per PoolId.
        id = key.toId();
        _poolInfo[id] = info;
        _baseOf[id] = base;
        _pools.push(id);
        emit PoolCreated(id, cfg.feed, msg.sender, key, cfg, info.configHash, synthetic);

        // A self call: PoolManager skips beforeInitialize when msg.sender == hook (Hooks.sol:170-181).
        tick = poolManager.initialize(key, sqrtPriceX96);
    }

    /// @dev Step 4 of SPEC 7.2: decimals read once with gas caps; returns the PoolInfo and the base token.
    function _buildInfo(PoolKey memory key, PoolConfig memory cfg, bool synthetic)
        private
        view
        returns (PoolInfo memory info, address base)
    {
        address quote;
        (base, quote) = cfg.baseIsCurrency0
            ? (Currency.unwrap(key.currency0), Currency.unwrap(key.currency1))
            : (Currency.unwrap(key.currency1), Currency.unwrap(key.currency0));
        info.cfg = cfg;
        info.baseDecimals = _tokenDecimals(base);
        info.quoteDecimals = _tokenDecimals(quote);
        info.feedDecimals = _feedDecimals(cfg.feed);
        if (cfg.quoteFeed != address(0)) info.quoteFeedDecimals = _feedDecimals(cfg.quoteFeed);
        info.synthetic = synthetic;
        info.creator = msg.sender;
        info.configHash = keccak256(abi.encode(cfg));
    }

    /// @dev Steps 4 and 5 of SPEC 7.2: the feeds are Fresh now, and the init price lies within
    ///      max(bandBps, INIT_BAND_FLOOR_BPS) bps of the anchor.
    function _checkInitPrice(PoolInfo memory info, uint160 sqrtPriceX96) private view {
        (Regime regime, uint256 anchor,) = _observeFeeds(info);
        if (regime != Regime.Fresh) revert FeedUnusable(_firstUnusableFeed(info));
        // Reverts InvalidSqrtPrice for a price PoolManager would refuse, before the price math below.
        TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        uint256 px = _priceX18(sqrtPriceX96, info.cfg.baseIsCurrency0, info.baseDecimals, info.quoteDecimals);
        uint256 gap = _gapBps(px, anchor);
        uint256 allowed = info.cfg.bandBps > INIT_BAND_FLOOR_BPS_ ? info.cfg.bandBps : INIT_BAND_FLOOR_BPS_;
        if (gap > allowed) revert InitPriceOffAnchor(gap);
    }

    /// @dev Step 3 of SPEC 7.2: every cfg field against the SPEC 5.2 bounds; BadConfig codes of SPEC 4.6.
    function _checkConfig(PoolConfig memory cfg, int24 tickSpacing) private view {
        if (cfg.baseFee < MIN_FEE_ || cfg.baseFee > BASE_FEE_CAP) revert BadConfig(1);
        if (cfg.maxFee < cfg.baseFee || cfg.maxFee > MAX_FEE_) revert BadConfig(2);
        if (cfg.bandBps > BAND_CAP) revert BadConfig(3);
        if (cfg.slope > SLOPE_CAP) revert BadConfig(4);
        if (cfg.staleAfter < STALE_MIN || cfg.staleAfter > STALE_MAX) revert BadConfig(5);
        if (cfg.feed == address(0) || cfg.feed.code.length == 0) revert BadConfig(6);
        if (cfg.quoteFeed != address(0) && (cfg.quoteFeed.code.length == 0 || cfg.quoteFeed == cfg.feed)) {
            revert BadConfig(7);
        }
        if (tickSpacing < TickMath.MIN_TICK_SPACING || tickSpacing > TickMath.MAX_TICK_SPACING) revert BadConfig(8);
    }

    function _canonical(address feed, bool baseIsCurrency0) private pure returns (PoolConfig memory) {
        return PoolConfig({
            feed: feed,
            quoteFeed: address(0),
            baseIsCurrency0: baseIsCurrency0,
            baseFee: CANON_BASE_FEE,
            maxFee: CANON_MAX_FEE,
            bandBps: CANON_BAND,
            slope: CANON_SLOPE,
            staleAfter: CANON_STALE,
            mode: FeeMode.Directional
        });
    }

    /// @dev True if `token` answers referenceFeed() with at least 32 bytes and a nonzero first word.
    function _declaresReference(address token) private view returns (bool) {
        (bool ok, uint256[5] memory w) = _read(token, SEL_REFERENCE_FEED, 32);
        return ok && w[0] != 0;
    }

    /// @dev Token decimals, gas capped; reverts BadDecimals if unreadable or above 18
    ///      (Bellguard defaulted to 18, BellHook.sol:399-404).
    function _tokenDecimals(address token) private view returns (uint8) {
        (bool ok, uint256[5] memory w) = _read(token, SEL_DECIMALS, 32);
        if (!ok || w[0] > 18) revert BadDecimals(token);
        return uint8(w[0]);
    }

    /// @dev Feed decimals, gas capped; reverts FeedUnusable if unreadable or outside [6, 18].
    function _feedDecimals(address feed) private view returns (uint8) {
        (bool ok, uint256[5] memory w) = _read(feed, SEL_DECIMALS, 32);
        if (!ok || w[0] < 6 || w[0] > 18) revert FeedUnusable(feed);
        return uint8(w[0]);
    }

    /// @dev The feed to name in FeedUnusable: the base feed unless only the quote feed fails.
    function _firstUnusableFeed(PoolInfo memory info) private view returns (address) {
        (bool ok,,) = _readFeed(info.cfg.feed, info.feedDecimals);
        if (ok && info.cfg.quoteFeed != address(0)) return info.cfg.quoteFeed;
        return info.cfg.feed;
    }

    // ------------------------------------------------------------------------------------------
    // Hook callbacks
    // ------------------------------------------------------------------------------------------

    /// @notice Every external PoolManager.initialize with this hook lands here and reverts: pools
    ///         exist only through createPool and createSyntheticPool.
    function _beforeInitialize(address, PoolKey calldata, uint160) internal pure override returns (bytes4) {
        revert OnlyViaCreatePool();
    }

    /// @notice Returns the fee of SPEC 7.3 with OVERRIDE_FEE_FLAG and a zero delta. Never reverts for a
    ///         pool created on this hook; hookData is ignored. The first swap of a block records the
    ///         pool price as the block-start price; params.sqrtPriceLimitX96 bounds that reading (_prices).
    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId id = key.toId();
        // block.number on an Arbitrum chain is the parent chain block number, so the window spans every
        // L2 block that shares it. The uint64 cast cannot truncate any real block number.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 bn = uint64(block.number);
        if (_blockStart[id].blockNumber != bn) _blockStart[id] = BlockStart(bn, _sqrtPriceX96(id));
        (uint24 fee,,,) = _quote(id, params.zeroForOne, params.sqrtPriceLimitX96);
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    // ------------------------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------------------------

    /// @inheritdoc IBellswapHook
    function poolInfo(PoolId id) external view returns (PoolInfo memory) {
        return _poolInfo[id];
    }

    /// @inheritdoc IBellswapHook
    function anchorPriceX18(PoolId id) external view returns (uint256 quotePerBaseX18, Regime regime, uint256 age) {
        PoolInfo memory info = _poolInfo[id];
        if (info.cfg.feed == address(0)) return (0, Regime.Broken, 0);
        return _observe(id, info);
    }

    /// @inheritdoc IBellswapHook
    function quoteFee(PoolKey calldata key, bool zeroForOne)
        external
        view
        returns (uint24 fee, uint256 gapBps, bool away, Regime regime)
    {
        return _quote(key.toId(), zeroForOne, 0);
    }

    /// @inheritdoc IBellswapHook
    function poolCount() external view returns (uint256) {
        return _pools.length;
    }

    /// @inheritdoc IBellswapHook
    function poolAt(uint256 index) external view returns (PoolId) {
        return _pools[index];
    }

    // ------------------------------------------------------------------------------------------
    // Fee curve (SPEC 7.3)
    // ------------------------------------------------------------------------------------------

    /// @dev The fee for one pool and direction: the larger of the SPEC 7.3 fees at the pre-swap price
    ///      and at the block-start reading of _prices (the pre-swap price when no swap happened yet in
    ///      this block); gap and away belong to the price that set the fee. `limit` is the swap's
    ///      sqrtPriceLimitX96, 0 for none (quoteFee). An unknown pool (no PoolInfo) returns MAX_FEE and
    ///      Broken; beforeSwap never sees one, since pools exist only through the creation functions.
    function _quote(PoolId id, bool zeroForOne, uint160 limit)
        private
        view
        returns (uint24 fee, uint256 gap, bool away, Regime regime)
    {
        PoolInfo memory info = _poolInfo[id];
        if (info.cfg.feed == address(0)) return (MAX_FEE_, 0, false, Regime.Broken);
        uint256 anchor;
        (anchor, regime,) = _observe(id, info);
        uint256 px;
        uint256 pxStart;
        if (anchor != 0) (px, pxStart) = _prices(id, info, zeroForOne, limit);
        (fee, gap, away) = _curve(info.cfg, regime, px, anchor, zeroForOne);
        if (pxStart != px) (fee, gap, away) = _higher(info.cfg, regime, pxStart, anchor, zeroForOne, fee, gap, away);
    }

    /// @dev The curve at `pxStart` if its fee is higher than `fee`, else (fee, gap, away) unchanged.
    function _higher(
        PoolConfig memory cfg,
        Regime regime,
        uint256 pxStart,
        uint256 anchor,
        bool zeroForOne,
        uint24 fee,
        uint256 gap,
        bool away
    ) private pure returns (uint24, uint256, bool) {
        (uint24 feeS, uint256 gapS, bool awayS) = _curve(cfg, regime, pxStart, anchor, zeroForOne);
        return feeS > fee ? (feeS, gapS, awayS) : (fee, gap, away);
    }

    /// @dev The pre-swap pool price and the block-start reading, both in _priceX18 units. The reading is
    ///      the block-start price, or the swap's price limit when that limit lies strictly between the
    ///      pre-swap and the block-start price: PoolManager never moves the price past the limit, so the
    ///      limit is the point of the swap's path nearest the block-start price, and a bounded trade near
    ///      the anchor is not charged the gap of a price it cannot reach. A limit on the wrong side of the
    ///      pre-swap price is ignored here (PoolManager reverts the swap with PriceLimitAlreadyExceeded).
    function _prices(PoolId id, PoolInfo memory info, bool zeroForOne, uint160 limit)
        private
        view
        returns (uint256 px, uint256 pxStart)
    {
        uint160 sp = _sqrtPriceX96(id);
        BlockStart memory bs = _blockStart[id];
        px = _priceX18(sp, info.cfg.baseIsCurrency0, info.baseDecimals, info.quoteDecimals);
        pxStart = px;
        if (bs.blockNumber == block.number && bs.sqrtPriceX96 != sp) {
            uint160 read = bs.sqrtPriceX96;
            if (zeroForOne ? (read < limit && limit < sp) : (sp < limit && limit < read)) read = limit;
            pxStart = _priceX18(read, info.cfg.baseIsCurrency0, info.baseDecimals, info.quoteDecimals);
        }
    }

    /// @dev The pure part of SPEC 7.3. Non-Fresh regimes charge maxFee in both directions. The
    ///      result is always in [cfg.baseFee, cfg.maxFee] for a cfg inside the SPEC 5.2 bounds, and
    ///      always in [MIN_FEE, MAX_FEE].
    function _curve(PoolConfig memory cfg, Regime regime, uint256 px, uint256 anchor, bool zeroForOne)
        internal
        pure
        returns (uint24 fee, uint256 gap, bool away)
    {
        uint256 f = cfg.maxFee;
        if (anchor != 0) {
            gap = _gapBps(px, anchor);
            bool buysBase = cfg.baseIsCurrency0 ? !zeroForOne : zeroForOne;
            away = (px >= anchor && buysBase) || (px <= anchor && !buysBase);
            if (regime == Regime.Fresh) {
                uint256 excess = gap > cfg.bandBps ? gap - cfg.bandBps : 0;
                uint256 gapFee = (cfg.mode == FeeMode.Symmetric || away) ? uint256(cfg.slope) * excess : 0;
                f = uint256(cfg.baseFee) + gapFee;
                if (f > cfg.maxFee) f = cfg.maxFee;
            }
        }
        if (f < MIN_FEE_) f = MIN_FEE_;
        if (f > MAX_FEE_) f = MAX_FEE_;
        // casting to uint24 is safe because f <= MAX_FEE_ = 100_000 on the line above
        // forge-lint: disable-next-line(unsafe-typecast)
        fee = uint24(f);
    }

    /// @dev Anchor, regime and age of a known pool. Settled takes precedence over the feed regimes.
    function _observe(PoolId id, PoolInfo memory info)
        private
        view
        returns (uint256 anchor, Regime regime, uint256 age)
    {
        (regime, anchor, age) = _observeFeeds(info);
        if (info.synthetic && !_isLive(_baseOf[id])) regime = Regime.Settled;
    }

    /// @dev Broken if a feed is unreadable, short, non-positive, above MAX_ANSWER or future-dated, or
    ///      if the anchor rounds to 0; Stale if a feed is older than staleAfter; Fresh otherwise.
    function _observeFeeds(PoolInfo memory info) private view returns (Regime regime, uint256 anchor, uint256 age) {
        (bool okB, uint256 usdB, uint256 ageB) = _readFeed(info.cfg.feed, info.feedDecimals);
        uint256 usdQ = SCALE;
        uint256 ageQ;
        bool okQ = true;
        if (info.cfg.quoteFeed != address(0)) {
            (okQ, usdQ, ageQ) = _readFeed(info.cfg.quoteFeed, info.quoteFeedDecimals);
        }
        if (!okB || !okQ) return (Regime.Broken, 0, 0);
        anchor = FullMath.mulDiv(usdB, SCALE, usdQ);
        if (anchor == 0) return (Regime.Broken, 0, 0);
        age = ageB > ageQ ? ageB : ageQ;
        regime = age > info.cfg.staleAfter ? Regime.Stale : Regime.Fresh;
    }

    /// @dev latestRoundData() through a gas-capped staticcall (Bellguard BellHook.sol:317-326, with
    ///      FEED_CALL_GAS, future updatedAt treated as Broken, and decimals normalisation).
    /// @return ok False if the call failed, returned fewer than 160 bytes, answered <= 0 or above
    ///         MAX_ANSWER, or reported updatedAt > block.timestamp.
    /// @return usd18 USD per whole unit, 18 decimals.
    /// @return age Seconds since updatedAt.
    function _readFeed(address feed, uint8 decimals) private view returns (bool ok, uint256 usd18, uint256 age) {
        uint256[5] memory w;
        (ok, w) = _read(feed, SEL_LATEST_ROUND_DATA, 160);
        if (!ok) return (false, 0, 0);
        // The answer word read as uint256: 0 and every negative int256 (top bit set) fail the range check.
        uint256 answer = w[1];
        uint256 updatedAt = w[3];
        // forge-lint: disable-next-line(block-timestamp)
        if (answer == 0 || answer > MAX_ANSWER || updatedAt > block.timestamp || decimals > 18) {
            return (false, 0, 0);
        }
        usd18 = answer * 10 ** (18 - decimals);
        age = block.timestamp - updatedAt;
    }

    /// @dev settlementState() of a synthetic through a gas-capped staticcall. Live only if the call
    ///      succeeds with at least 96 bytes and the phase word is 0.
    function _isLive(address synth) private view returns (bool) {
        (bool ok, uint256[5] memory w) = _read(synth, SEL_SETTLEMENT_STATE, 96);
        return ok && w[0] == 0;
    }

    // ------------------------------------------------------------------------------------------
    // Math
    // ------------------------------------------------------------------------------------------

    /// @dev |px - anchor| * 1e4 / anchor, saturating at GAP_SATURATION (Bellguard BellHook.sol:330-335).
    function _gapBps(uint256 px, uint256 anchor) internal pure returns (uint256) {
        uint256 diff = px > anchor ? px - anchor : anchor - px;
        if (diff / anchor >= GAP_SATURATION / BPS) return GAP_SATURATION;
        return FullMath.mulDiv(diff, BPS, anchor);
    }

    /// @dev Whole quote tokens per whole base token times 1e18, from sqrtPriceX96 (Bellguard
    ///      BellHook.sol:357-362). priceX192 = sqrtPriceX96^2 is currency1 raw units per currency0
    ///      raw unit times 2^192. Decimals are bounded to 18 at creation and sqrtPriceX96 lies in
    ///      [MIN_SQRT_PRICE, MAX_SQRT_PRICE), so no step overflows. 0 for sqrtPriceX96 == 0.
    function _priceX18(uint160 sqrtPriceX96, bool baseIsCurrency0, uint8 baseDec, uint8 quoteDec)
        internal
        pure
        returns (uint256)
    {
        if (sqrtPriceX96 == 0) return 0;
        uint256 num = SCALE * 10 ** baseDec;
        uint256 den = 10 ** quoteDec;
        if (sqrtPriceX96 <= type(uint128).max) {
            uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
            if (baseIsCurrency0) return FullMath.mulDiv(priceX192, num, den << 192);
            return FullMath.mulDiv(uint256(1) << 192, num, priceX192) / den;
        }
        uint256 priceX128 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 64);
        if (baseIsCurrency0) return FullMath.mulDiv(priceX128, num, den << 128);
        return FullMath.mulDiv(uint256(1) << 128, num, priceX128) / den;
    }

    /// @dev sqrtPriceX96 from PoolManager slot0 via extsload, the same read as StateLibrary.getSlot0
    ///      (lib/v4-core/src/libraries/StateLibrary.sol:40-56) without importing StateLibrary, whose
    ///      import of Position.sol (BUSL-1.1) would enter the hook's source tree.
    function _sqrtPriceX96(PoolId id) private view returns (uint160) {
        bytes32 slot = keccak256(abi.encodePacked(PoolId.unwrap(id), POOLS_SLOT));
        return uint160(uint256(poolManager.extsload(slot)));
    }

    // ------------------------------------------------------------------------------------------
    // Bounded staticcall
    // ------------------------------------------------------------------------------------------

    /// @dev staticcall(target, selector) with FEED_CALL_GAS; copies at most 160 bytes of return data
    ///      (no return-data bomb). ok is false if the call reverted or returned fewer than minSize bytes.
    function _read(address target, bytes4 selector, uint256 minSize)
        private
        view
        returns (bool ok, uint256[5] memory w)
    {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, selector)
            let success := staticcall(FEED_CALL_GAS_, target, ptr, 4, w, 160)
            ok := and(success, iszero(lt(returndatasize(), minSize)))
        }
    }
}
