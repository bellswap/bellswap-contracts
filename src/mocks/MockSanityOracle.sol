// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IMockSanityOracle
/// @notice Test fixture interface (SPEC 4.9): the sanity oracle getter ABI plus posting functions. Test only.
interface IMockSanityOracle {
    error NotPoster();
    error PriceNotSet();
    error StalePrice();
    error PriceOutOfRange();
    error InvalidAddress();

    event PricePosted(
        address indexed token, uint256 lastPricePosted, uint256 lastUpdated, uint256 newPrice, uint256 updateAt
    );
    event MaxTimeDelaySet(address indexed token, uint256 maxTimeDelay);

    /// @notice The only address allowed to post, or address(0) when anyone may post.
    function POSTER() external view returns (address);
    /// @notice (price, lastUpdated, maxTimeDelay, allowedDeviationBps); zeros for a token never posted.
    function prices(address token) external view returns (uint256, uint64, uint32, uint16);
    /// @notice Reverts unless `price` is within the token's allowed deviation of a fresh posted price.
    function validatePrice(address token, uint256 price) external view;
    /// @notice Validity window given to a token at its first post: 172_800 s.
    function defaultMaxTimeDelay() external view returns (uint32);
    /// @notice Allowed deviation given to a token at its first post: 1_000 bps.
    function defaultDeviationBps() external view returns (uint16);
    /// @notice Posts `price` for `token` at block.timestamp.
    function postPrice(address token, uint256 price) external;
    /// @notice Posts several prices at block.timestamp.
    function postPrices(address[] calldata tokens, uint256[] calldata tokenPrices) external;
    /// @notice Posts `price` for `token` at an arbitrary `timestamp` (backdate or future-date).
    function postPriceAt(address token, uint256 price, uint64 timestamp) external;
}

/// @title MockSanityOracle
/// @notice Own MIT test fixture with the sanity oracle getter ABI (SPEC 4.9, 6.7). Sepolia and unit tests only,
/// never mainnet. constructor(poster): poster == 0 means anyone can post (the open mock of stack O); otherwise
/// only poster can post (the demo mock of stack D). No owner and no other privileged function.
/// postPrice and postPrices reject a zero price; postPriceAt stores any price and timestamp so tests and scenarios
/// can produce zero, out-of-range, stale and future-dated observations.
contract MockSanityOracle is IMockSanityOracle {
    struct PriceData {
        uint256 price;
        uint64 lastUpdated;
        uint32 maxTimeDelay;
        uint16 allowedDeviationBps;
    }

    uint32 private constant _DEFAULT_MAX_TIME_DELAY = 172_800;
    uint16 private constant _DEFAULT_DEVIATION_BPS = 1_000;

    /// @inheritdoc IMockSanityOracle
    address public immutable POSTER;

    mapping(address token => PriceData) private _prices;

    /// @param poster The only poster, or address(0) for an open mock.
    constructor(address poster) {
        POSTER = poster;
    }

    modifier onlyPoster() {
        if (POSTER != address(0) && msg.sender != POSTER) revert NotPoster();
        _;
    }

    /// @inheritdoc IMockSanityOracle
    function defaultMaxTimeDelay() external pure returns (uint32) {
        return _DEFAULT_MAX_TIME_DELAY;
    }

    /// @inheritdoc IMockSanityOracle
    function defaultDeviationBps() external pure returns (uint16) {
        return _DEFAULT_DEVIATION_BPS;
    }

    /// @inheritdoc IMockSanityOracle
    function prices(address token) external view returns (uint256, uint64, uint32, uint16) {
        PriceData memory d = _prices[token];
        return (d.price, d.lastUpdated, d.maxTimeDelay, d.allowedDeviationBps);
    }

    /// @inheritdoc IMockSanityOracle
    /// @dev PriceNotSet if never posted or zero; StalePrice if older than maxTimeDelay (saturating, a future
    /// lastUpdated is fresh); PriceOutOfRange if |price - posted| * 1e4 > allowedDeviationBps * posted.
    function validatePrice(address token, uint256 price) external view {
        PriceData memory d = _prices[token];
        if (d.price == 0 || d.lastUpdated == 0) revert PriceNotSet();
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > d.lastUpdated && block.timestamp - d.lastUpdated > d.maxTimeDelay) revert StalePrice();
        uint256 diff = price > d.price ? price - d.price : d.price - price;
        if (diff * 1e4 > uint256(d.allowedDeviationBps) * d.price) revert PriceOutOfRange();
    }

    /// @inheritdoc IMockSanityOracle
    function postPrice(address token, uint256 price) external onlyPoster {
        if (price == 0) revert PriceOutOfRange();
        _post(token, price, uint64(block.timestamp));
    }

    /// @inheritdoc IMockSanityOracle
    /// @dev Reverts InvalidAddress when the arrays differ in length.
    function postPrices(address[] calldata tokens, uint256[] calldata tokenPrices) external onlyPoster {
        if (tokens.length != tokenPrices.length) revert InvalidAddress();
        for (uint256 i; i < tokens.length; ++i) {
            if (tokenPrices[i] == 0) revert PriceOutOfRange();
            _post(tokens[i], tokenPrices[i], uint64(block.timestamp));
        }
    }

    /// @inheritdoc IMockSanityOracle
    function postPriceAt(address token, uint256 price, uint64 timestamp) external onlyPoster {
        _post(token, price, timestamp);
    }

    function _post(address token, uint256 price, uint64 timestamp) private {
        if (token == address(0)) revert InvalidAddress();
        PriceData storage d = _prices[token];
        if (d.maxTimeDelay == 0) {
            d.maxTimeDelay = _DEFAULT_MAX_TIME_DELAY;
            d.allowedDeviationBps = _DEFAULT_DEVIATION_BPS;
            emit MaxTimeDelaySet(token, _DEFAULT_MAX_TIME_DELAY);
        }
        uint256 last = d.price;
        d.price = price;
        d.lastUpdated = timestamp;
        emit PricePosted(token, last, timestamp, price, timestamp);
    }
}
