# Bellswap contracts

Bellswap is a Uniswap v4 hook and a synthetic market on Robinhood Chain. The hook sets the swap fee from the gap between the pool price and a reference price relayed from Ethereum: 0.30% inside a 10% gap, rising to 3% as the gap widens, and 3% in both directions when the reference is stale. bsX0 is a synthetic of the BWET reference, minted against USDG at 400% collateral.

**Unaudited. Use at your own risk. Real funds.**

## Deployed on mainnet

| Contract | Chain | Address | Explorer |
| --- | --- | --- | --- |
| Ethereum relay (BellswapRelay) | Ethereum | 0xe0D5f55480705E9e11B6e8d3b53B7e401Cd17645 | https://etherscan.io/address/0xe0D5f55480705E9e11B6e8d3b53B7e401Cd17645 |
| ReferenceFeedFactory | Robinhood Chain (4663) | 0x6f56B432f66b906E9488aB4889d8746055861f74 | https://robinhoodchain.blockscout.com/address/0x6f56B432f66b906E9488aB4889d8746055861f74 |
| Reference feed | Robinhood Chain (4663) | 0xA8Dd192FFcAcC451D104BEEB628190ab4D3aA6ad | https://robinhoodchain.blockscout.com/address/0xA8Dd192FFcAcC451D104BEEB628190ab4D3aA6ad |
| BellswapHook | Robinhood Chain (4663) | 0xe136bc1a37Fa63cbD7051D0545572a69F815A080 | https://robinhoodchain.blockscout.com/address/0xe136bc1a37Fa63cbD7051D0545572a69F815A080 |
| BellMarketFactory | Robinhood Chain (4663) | 0xf5Ff223212d0f3D8E17116966190Fac321a1AfA9 | https://robinhoodchain.blockscout.com/address/0xf5Ff223212d0f3D8E17116966190Fac321a1AfA9 |
| Market bsX0 | Robinhood Chain (4663) | 0xDfEd3508dcb50D760e3F2F2dd49dCFd67E12B0b3 | https://robinhoodchain.blockscout.com/address/0xDfEd3508dcb50D760e3F2F2dd49dCFd67E12B0b3 |
| Market bsX1 (unused) | Robinhood Chain (4663) | 0xb571038e0Bae210cdBA52C4C197ee1446f54d105 | https://robinhoodchain.blockscout.com/address/0xb571038e0Bae210cdBA52C4C197ee1446f54d105 |

Pool id: 0x1c45f406c6ce0ee24c8b10172e2af4da7780962e2f242a4795c0a5cdf46633c2

The pool lives on the Uniswap v4 PoolManager at 0x8366a39CC670B4001A1121B8F6A443A643e40951 (https://robinhoodchain.blockscout.com/address/0x8366a39CC670B4001A1121B8F6A443A643e40951).

## Source of record

This repo holds the exact `src` tree the mainnet contracts were built from (private commit 95c610d). The git tree hash of `src` at that commit is `31f74163bca3af1cfee05a77bb0f4b4ec2ecdf8f`. Tests and deployment scripts are not included.

Main contracts:

- `src/hook/BellswapHook.sol`
- `src/mint/BellMarketFactory.sol`
- `src/mint/BellMarket.sol`
- `src/reference/l2/ReferenceFeedFactory.sol`
- `src/reference/l2/ReferenceFeed.sol`
- `src/reference/l2/GuardedFeedView.sol`
- `src/reference/l1/BellswapRelay.sol`

## Build

Requires [Foundry](https://book.getfoundry.sh/). Dependencies are cloned at pinned commits (forge-std 886b4f8b, openzeppelin-contracts cab19933, v4-core e50237c4 with its submodules) into `lib/`, which is git-ignored.

```
bash tools/install-deps.sh
forge build
```

The build uses Solc 0.8.26. The compiler reports no warnings; forge-lint reports style warnings (`block-timestamp`, `unsafe-typecast`).

## Links

- https://bellswap.fun
- https://status.bellswap.fun
- https://chart.bellswap.fun

## License

See [LICENSE](LICENSE) and [NOTICE](NOTICE).

Not affiliated with Robinhood Markets, Inc. or Ondo.
