# Bellswap audit scope

Unaudited. Prepared for an external review; scope frozen at the tags named below.

Bellswap is a Uniswap v4 hook and a set of synthetic markets on Robinhood Chain (chain id 4663). A relay on Ethereum reads a reference price and sends it to Robinhood Chain as an Arbitrum retryable ticket; a reference feed there guards the price; the hook sets each swap fee from the gap between the pool price and that reference; the markets mint synthetic ERC-20 tokens against USDG collateral at the reference price. Audit-ready date: 14 October 2026.

The code lives in two public repositories:

| Repository | Holds | Commit described here |
|---|---|---|
| https://github.com/bellswap/bellswap-contracts | Hook, reference layer (relay, feed factory, feed, guarded view), v1 market and factory | `72f72258bebcf7679a3d29a202a9a342530e54ca` (main); `src/` tree hash `31f74163bca3af1cfee05a77bb0f4b4ec2ecdf8f` |
| https://github.com/bellswap/bellswap-markets | V2 market, V2 and V3 factories, their tests and the TANKR deploy scripts | the commit tagged `tankr-mainnet-2026-10-07` (`ef1039e9877948457ca090347f67823b3fcbfee8`); `src/` tree hash `6764f1b26786ca189cf898bb719c06c0d24315fa` |

Every `src/` file present in both repositories (21 files), and `LICENSE` and `remappings.txt`, is byte-identical (same git blob). `foundry.toml`, `tools/install-deps.sh`, `.gitignore` and `README.md` differ between the two repositories (section 3). Both trees were exported from a private development repository: bellswap-contracts `src/` equals private commit 95c610d (the reviewed and deployed commit), and every `src/`, `test/` and `script/lib/` file in bellswap-markets equals private commit 37b342e. That private commit is also where the full test suite and the coverage run below live.

## 1. Scope

### 1.1 Deployed contracts

Every row is verified on Sourcify (`https://sourcify.dev/server/v2/contract/<chainId>/<address>`) as an exact match for both creation and runtime bytecode, with compiler 0.8.26+commit.8a97fa7a, EVM cancun, optimizer 800 runs, viaIR false. Every project source file in each Sourcify record is identical to the file of the same path in the repository named in the row. Deploy blocks and transactions are from the same Sourcify records.

| Contract | Repository and path | Chain | Address | Deployed (UTC date, block) | Sourcify exact match | Lines (total / code) |
|---|---|---|---|---|---|---|
| BellswapRelay | bellswap-contracts `src/reference/l1/BellswapRelay.sol` | Ethereum (1) | `0xe0D5f55480705E9e11B6e8d3b53B7e401Cd17645` | 2026-10-02, block 26107573 | yes | 315 / 219 |
| ReferenceFeedFactory | bellswap-contracts `src/reference/l2/ReferenceFeedFactory.sol` | Robinhood Chain (4663) | `0x6f56B432f66b906E9488aB4889d8746055861f74` | 2026-10-02, block 78584550 | yes | 161 / 116 |
| ReferenceFeed (`SUBJECT()` `0xEcA55ac71f83931B7e074228AEBc9104F13d8c02`, shown as BWET on bellswap.fun) | bellswap-contracts `src/reference/l2/ReferenceFeed.sol` | Robinhood Chain (4663) | `0xA8Dd192FFcAcC451D104BEEB628190ab4D3aA6ad` | 2026-10-02, block 78584663 | yes | 561 / 394 |
| GuardedFeedView | bellswap-contracts `src/reference/l2/GuardedFeedView.sol` | Robinhood Chain (4663) | `0x33e0BE748CBF8b283CDc0Cb9C9C809a78B1A16c4` | 2026-10-02, block 78584666 | yes | 92 / 62 |
| BellswapHook | bellswap-contracts `src/hook/BellswapHook.sol` (inherits `src/hook/BaseHook.sol`, 236 / 178) | Robinhood Chain (4663) | `0xe136bc1a37Fa63cbD7051D0545572a69F815A080` | 2026-10-04, block 80041677 | yes | 579 / 383 |
| BellMarketFactory (v1) | bellswap-contracts `src/mint/BellMarketFactory.sol` | Robinhood Chain (4663) | `0xf5Ff223212d0f3D8E17116966190Fac321a1AfA9` | 2026-10-04, block 80041886 | yes | 195 / 151 |
| BellMarket, market bsX0 | bellswap-contracts `src/mint/BellMarket.sol` (uses `src/mint/MarketMath.sol`, 129 / 92) | Robinhood Chain (4663) | `0xDfEd3508dcb50D760e3F2F2dd49dCFd67E12B0b3` | 2026-10-04, block 80043409 | yes | 569 / 458 |
| BellMarket, market bsX1 (unused, same code as bsX0) | bellswap-contracts `src/mint/BellMarket.sol` | Robinhood Chain (4663) | `0xb571038e0Bae210cdBA52C4C197ee1446f54d105` | 2026-10-04, block 80043513 | yes | same file |
| BellMarketFactoryV3 | bellswap-markets `src/mint/BellMarketFactoryV3.sol` | Robinhood Chain (4663) | `0x5c4B9baf485D1B72f46Ef84889c33CBca99f3D1E` | 2026-10-07, block 82569133 | yes | 338 / 241 |
| BellMarketV2, market 100 Tanker (TANKR) | bellswap-markets `src/mint/BellMarketV2.sol` (uses `src/mint/MarketMath.sol`) | Robinhood Chain (4663) | `0x0B199dA32205A5986f8DBDbed1b9c9c86FD7B3f2` | 2026-10-07, block 82570621 | yes | 577 / 460 |

Deploy transactions: relay `0x7ea65bab7bcbce7be2db1f2a102f0c53c7bbcd6468effd1b31d2e56770f5c2b7`; feed factory `0x9a465e125c0a1f1689b04070d8abfad5fe723439427d4fffd83ec369d886d1c1`; feed `0x886849aa33d33b496e183f3860197d599af1f145a8cddfc397b648503193b047`; guarded view `0x28e1c345388baea86bb9379ee38f3413be70509df645d581ae745e4009021c7d`; hook `0xf39379f1e7c9c3cd398e219109b8e6bc3be1cff7d42fd098189302fc84aaa053`; v1 factory `0x54994fdbdcd4feb7b91136206494d47c6dca989967a36c7b39624c6118796800`; bsX0 `0x7f14ac5f102ff1607ebd117079a5b4986067cb7fb61b4cafcfc2b9ed48ac9dd7`; bsX1 `0x56244f75404597d5c80f18c9383c91a322e505c519ca2c7f18f4b9da6f014c5d`; V3 factory `0x0003cdf7cd4884691b090edb9cfe54f261625a6df578859b8e1cb7c23eca82f7`; TANKR `0x5ef560af00c4f1331f1c542e5c7e9337c826337fc1447cb808c21bd30f71b2b5`.

On-chain wiring (eth_call on Robinhood Chain, 8 October 2026): bsX0 `FACTORY()` is the v1 factory, `FEED()` is the ReferenceFeed, `referenceFeed()` is the GuardedFeedView; the v1 factory holds two markets (bsX0, bsX1); TANKR `FACTORY()` is the V3 factory and `FEED()` is the same ReferenceFeed; the V3 factory holds one market; ReferenceFeedFactory `L1_RELAY()` is the BellswapRelay above; both markets' `USDG()` is `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`. The hook serves two pools on the Uniswap v4 PoolManager `0x8366a39CC670B4001A1121B8F6A443A643e40951`: `0x1c45f406c6ce0ee24c8b10172e2af4da7780962e2f242a4795c0a5cdf46633c2` (USDG/bsX0) and `0x6728e02c29014a5f4703c4367f0638a35351dbc8a5e9a85de91829896da0641f` (the TANKR pool).

### 1.2 In scope, not deployed

| Contract | Repository and path | Lines (total / code) |
|---|---|---|
| BellMarketFactoryV2 | bellswap-markets `src/mint/BellMarketFactoryV2.sol` | 323 / 239 |

BellMarketFactoryV3 is BellMarketFactoryV2 with lower tier bounds and the full bonus rule, written as a separate file, and both deploy the same BellMarketV2 code. The V2 factory is built and tested but has no mainnet deployment.

### 1.3 Supporting files in scope

Compiled into the contracts above: `src/hook/BaseHook.sol` (236 / 178), `src/hook/IBellswapHook.sol` (166 / 78), `src/mint/MarketMath.sol` (129 / 92), `src/mint/interfaces/IBellMarket.sol` (207 / 144), `IBellMarketFactory.sol` (104 / 63), `IBellMarketFactoryV2.sol` (144 / 73, bellswap-markets only), `IMarketReference.sol` (54 / 31), `IReferenced.sol` (14 / 5), `src/reference/l1/BellTypes.sol` (30 / 19), `IAggregatorV3.sol` (23 / 14), `IBellswapRelay.sol` (89 / 55), the kind 1 price-source interface in the same folder (13 / 7), `IReferenceFeedReport.sol` (13 / 5), `src/reference/l2/ReferenceDescription.sol` (16 / 9), `src/reference/l2/interfaces/IGuardedFeedView.sol` (23 / 12), `IReferenceFeed.sol` (135 / 81), `IReferenceFeedFactory.sol` (68 / 38). `src/reference/l1/ISanityOracle.sol` (6 / 2) is a re-export of that price-source interface that nothing imports.

### 1.4 Line counts

"Code" counts non-blank lines after removing `//` and `/* */` comments; `cloc` gives the same code figures for every set below.

| Set | Files | Total lines | Code lines |
|---|---|---|---|
| Full scope: sections 1.1 to 1.3 (bellswap-contracts `src/` without mocks, vendor and `src/Version.sol`, plus the four files new in bellswap-markets: BellMarketV2, BellMarketFactoryV2, BellMarketFactoryV3, IBellMarketFactoryV2) | 28 | 5,180 | 3,629 |
| bellswap-contracts part of the full scope | 24 | 3,798 | 2,616 |
| bellswap-markets files new relative to bellswap-contracts | 4 | 1,382 | 1,013 |
| Deployed-bytecode set: union of the `src/` files in the ten Sourcify records | 28 | 4,935 | 3,420 |

The two 28-file sets differ: the deployed-bytecode set adds the vendor files `src/vendor/AddressAliasHelper.sol` and `src/vendor/IInboxMinimal.sol`, which are compiled into ReferenceFeedFactory and BellswapRelay, and drops BellMarketFactoryV2 (not deployed) and ISanityOracle (not imported).

### 1.5 Deployed parameters

Read with eth_call on Robinhood Chain on 8 October 2026, at the latest block (block 83323035, and again at block 83352774 with the same values). The public RPC `https://rpc.mainnet.chain.robinhood.com` serves no historical state, so the reads reproduce at the latest block only. The market values are immutables or constants. The factory tier and label menus and the hook pool records are storage, written once (menus in the factory constructor, a pool record when its pool is created, `src/hook/BellswapHook.sol:215`) and never changed by any function. The feed configuration at the end of this section can change (section 5). USDG and USD amounts have 6 decimals.

| Market getter | bsX0 (market 0) | bsX1 (market 1) | TANKR (market 100) |
|---|---|---|---|
| `MARKET_ID` | 0 | 1 | 100 |
| `CAP_USD` | 25,000 USD | 25,000 USD | 10,000 USD |
| `MINT_CR_BPS` (mint and withdraw floor) | 40,000 | 40,000 | 17,500 |
| `LIQ_CR_BPS` (liquidation threshold) | 25,000 | 25,000 | 15,000 |
| `BONUS_BPS` (liquidation bonus) | 1,500 | 1,500 | 500 |
| `BUFFER_FLOOR_BPS` (minimum mint buffer) | 1,000 | 1,000 | 1,000 |
| `MINT_MAX_AGE` | 172,800 s | 172,800 s | 129,600 s |
| `LIQ_MAX_AGE` | 259,200 s | 259,200 s | 259,200 s |
| `SETTLE_STALE` | 604,800 s | 604,800 s | 604,800 s |
| `SETTLE_GCR_BPS` (global settlement trigger) | 11,000 | 11,000 | 10,500 |
| `MIN_COLLATERAL` | 100 USDG | 100 USDG | 100 USDG |
| `MIN_DEBT_VALUE` | 50 USD | 50 USD | 50 USD |
| `DISC_BASE` | 0 | 0 | 0 |

Constants in both market contracts: `MAX_BUFFER_BPS` 3,000, `LAG_GRACE` 7,200 s, `ARM_DELAY` 86,400 s (`src/mint/BellMarket.sol:27-31`, `src/mint/BellMarketV2.sol:31-35`).

Factory menus (`tierCount()`, `tier(i)`): the v1 factory holds two tiers with the bsX0 values above, warm-up 259,200 s (tier 0) and 0 s (tier 1). The V3 factory holds one tier with the TANKR values above and a warm-up of 600 s, and one label.

Hook pools (`poolInfo(id)` on the hook): both pools, USDG/bsX0 `0x1c45f406...33c2` and TANKR `0x6728e02c...641f`, are synthetic pools with feed = the GuardedFeedView, no quote feed, `baseFee` 3,000 pips, `maxFee` 30,000 pips, `bandBps` 1,000, `slope` 100, `staleAfter` 194,400 s and mode Directional. `baseIsCurrency0` is false for the bsX0 pool and true for the TANKR pool. The GuardedFeedView has `MAX_AGE` 0 (no age check).

Feed configuration relayed from the reference source (`config()` on the ReferenceFeed, set from L1 block 26145140): `deviationBps` 1,000, `maxTimeDelay` 172,800 s. These two values can change after deployment (section 5).

## 2. Out of scope

- `src/mocks/` (4 files in bellswap-contracts, `MockUSDG.sol` in bellswap-markets): test tokens and oracles.
- `src/vendor/`: `AddressAliasHelper.sol` (unmodified Apache-2.0 code from OffchainLabs token-bridge-contracts), `IInboxMinimal.sol` (a minimal Inbox interface), `HookMiner.sol` (unmodified MIT code from Uniswap v4-periphery commit dce236d4e2057422d0791d9a973a58765eb46f65, used only off-chain to mine the hook address). The first two are compiled into deployed bytecode; their use in ReferenceFeedFactory and BellswapRelay is in scope, the vendored code itself is not.
- `src/Version.sol`.
- `script/` and `test/` in both repositories, including the TANKR deploy scripts in bellswap-markets.
- Dependencies in `lib/`: forge-std, OpenZeppelin Contracts, Uniswap v4-core (section 4).
- The website, the indexer and the chart service.
- The keeper: an off-chain bot that relays prices and liquidates positions. It holds no special rights on-chain (section 5).
- The relay's Ethereum-side dependencies, named here and trusted, not owned: the Arbitrum delayed Inbox of Robinhood Chain (`0x1a07cc4bd17e0118bdb54d70990d2158abad7a2d`, relay constructor argument `inbox`) with its Bridge, and the reference source the relay reads (`0x914D5Cb27cb30E80BdE8215ff577eD63Eb986B79`, the relay's second constructor argument, the ReferenceFeed's `SOURCE()`; feed `KIND()` 1, `SUBJECT()` `0xEcA55ac71f83931B7e074228AEBc9104F13d8c02`).
- The Uniswap v4 PoolManager and periphery on Robinhood Chain, and the USDG token.

## 3. Compiler and build

| Setting | Value | Source |
|---|---|---|
| Solidity | 0.8.26 | `foundry.toml` `solc_version` |
| EVM version | cancun | `foundry.toml` `evm_version` |
| Optimizer | on, 800 runs | `foundry.toml` `optimizer`, `optimizer_runs` |
| via-IR | off | `foundry.toml` `via_ir = false` |
| Remappings | `remappings.txt` only (forge-std/, @openzeppelin/contracts/, @uniswap/v4-core/, v4-core/, solmate/) | `foundry.toml` `auto_detect_remappings = false` |
| Foundry | forge 1.7.1 (commit 4072e48) for the build, test and coverage runs below | `forge --version` |

The compiler values of `[profile.default]` (solc, EVM version, optimizer, via-IR, `auto_detect_remappings`) and `remappings.txt` are the same in both repositories and match every Sourcify compilation record. The two `foundry.toml` files differ otherwise: bellswap-contracts adds `fs_permissions`, the profiles `c1` to `c4`, `invariant` and `fork`, and `[rpc_endpoints]`, which the private test suite uses; bellswap-markets defines `c4` and `invariant` only as artifact and cache folders (section 7).

bellswap-contracts (no tests in this repository):

```
bash tools/install-deps.sh
forge build
```

On 8 October 2026 at `72f7225`, with `lib/` at the three pinned commits, `forge build --offline` compiled 71 files with Solc 0.8.26 and exited 0. forge-lint prints style notes (`unsafe-typecast`, `block-timestamp`).

bellswap-markets:

```
bash tools/install-deps.sh
forge build
forge test
```

On 8 October 2026 at `ef1039e`, `forge test --summary --offline` ran 35 suites: 328 passed, 0 failed, 0 skipped, exit 0.

In bellswap-contracts, `tools/install-deps.sh` (line 2) and `NOTICE` refer to `docs/DEPENDENCIES.md`, which is not in the public repository (line 2 of the bellswap-markets copy points to its README instead); the pins are in `tools/install-deps.sh` lines 13 to 15 and in section 4.

## 4. Dependencies

Plain clones into `lib/` by `tools/install-deps.sh` (no git submodules in the Bellswap repositories; the pin lists are identical in both).

| Dependency | Upstream | Commit | Version |
|---|---|---|---|
| forge-std | https://github.com/foundry-rs/forge-std | `886b4f8b63409ef474542de6394d25a9b5908ed3` | no tag at the commit; master after v1.16.2 |
| OpenZeppelin Contracts | https://github.com/OpenZeppelin/openzeppelin-contracts | `cab19933c33c2ad1d4c7a84864a3601dddfd16f3` | v5.7.0 |
| Uniswap v4-core | https://github.com/Uniswap/v4-core | `e50237c43811bd9b526eff40f26772152a42daba` | v4.0.0, fetched with its submodules |

Nested v4-core submodules: lib/forge-std `1de6eecf821de7fe2c908cc48d3ab3dced20717f`, lib/openzeppelin-contracts `dbb6104ce834628e473d2173bbc9d47f81a9eec3`, lib/solmate `4b47a19038b798b4a33d9749d25e570443520647` (remapped as `solmate/`, never imported from `src/`).

Imports from `src/` resolve only to `@openzeppelin/contracts` (ERC20, IERC20, IERC20Metadata, SafeERC20, Math, SafeCast, ReentrancyGuardTransient, Strings) and `@uniswap/v4-core/src` (IHooks, IPoolManager, FullMath, Hooks, LPFeeLibrary, TickMath, BalanceDelta, BeforeSwapDelta, Currency, PoolId, PoolKey). The V2 and V3 contracts add no other external imports.

## 5. Trust model and actors

- No privileged roles. No contract in scope has an owner, admin, pause, upgrade path, proxy, `delegatecall` or `selfdestruct`. Bellswap configuration is set in constructors and stored as immutables or constants (live values in section 1.5); the factory tier and label menus are written once in the constructor, and each hook pool record once when its pool is created. No account can change it after deployment; a fix means a new deployment. The one setting that changes after deployment is the reference source's own configuration, relayed into the feed (next two items).
- Relay (Ethereum). Anyone can call the relay's two relay functions (kind 1 source at `src/reference/l1/BellswapRelay.sol:130`, aggregators at :143) and pay the retryable ticket. The relay reads the reference source (the immutable source address set in the constructor, :46) and sends the report through the Arbitrum delayed Inbox (`INBOX`). It trusts the Inbox and its Bridge to deliver the message with the L1-to-L2 address alias. It trusts the reference source for the price and for two configuration values it forwards with every report: the source's per-token `deviationBps` and `maxTimeDelay` (:177-197).
- ReferenceFeedFactory and ReferenceFeed (Robinhood Chain). `report` accepts calls only from the aliased relay address (`L1_RELAY_ALIAS`); `ReferenceFeed.push` accepts calls only from its factory. The feed guards the price (pending episodes, hold, epoch anchor, discontinuity record); the markets and the hook read the feed or the GuardedFeedView. The source's configurer can change `deviationBps` and `maxTimeDelay` without a new observation; a relayed report that carries the latest round's price is applied as a configuration-only update (`src/reference/l2/ReferenceFeed.sol:281`, `_configOnly` :349-352, read through `config()` :226). The markets use the relayed `deviationBps` as the mint price buffer, `max(deviationBps, BUFFER_FLOOR_BPS)`, and close minting while it is above `MAX_BUFFER_BPS` 3,000 (`src/mint/BellMarket.sol:500-512`, `src/mint/BellMarketV2.sol:508-520`). The reference source therefore sets the mint price markup and can close minting in every market, independently of the price. `maxTimeDelay` is stored, but no age check in scope reads it (reference-7, section 6.2).
- Hook. Permissionless pool creation through `createPool` and `createSyntheticPool`, with the start price checked against the reference. The hook only sets the dynamic fee; it does not gate adding or removing liquidity.
- Markets. Anyone can open a position, deposit USDG, mint against it, repay, withdraw and close their own position; anyone can liquidate a position below the liquidation ratio (`IBellMarket.liquidate`, "Anyone liquidates a position below LIQ_CR") and anyone can trigger settlement when its conditions hold.
- Keeper. An off-chain, permissionless bot that relays prices and liquidates. It has no on-chain rights beyond those of any account; liquidation and relay liveness depend on someone calling these functions.
- USDG (`0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`) is the collateral of every market and one side of each pool. It is an external token; any controls its issuer has over transfers are outside this scope and are not modelled.
- Uniswap v4 PoolManager (`0x8366a39CC670B4001A1121B8F6A443A643e40951`) is trusted to call the hook as specified by v4-core v4.0.0.

## 6. Known issues

Full write-ups with reproduction tests are available to the reviewing firm on request at hi@bellswap.fun.

Every item in this section is open and unfixed in the deployed code. The contracts cannot be upgraded.

- 6.1: seven findings of the internal review of 2 October 2026 (section 9), each with a suggested fix.
- 6.2: ten further findings of the same review, all P3.
- 6.3: residual paths of the TANKR tier, measured in the review rounds of the V2 and V3 code (section 9).
- 6.4: accepted residual risks of the design, from the threat model of the Bellswap specification.

### 6.1 Findings with a suggested fix

The hook, the v1 factory and the markets bsX0 and bsX1 were deployed on 4 October 2026, and TANKR on 7 October 2026, with these findings unfixed. mint-1 applies to both BellMarket (bsX0, bsX1) and BellMarketV2 (the live TANKR market), which has the same settlement trigger expression.

Line numbers refer to the files in this repository (`72f7225`) or in bellswap-markets (`ef1039e`); the reviewed files are byte-identical to them. Severity is the final rating of the internal review (P2 above P3).

| id | Contract | Severity | Status |
|---|---|---|---|
| hook-1 | BellswapHook | P2 | open, disclosed, unfixed in the deployed code |
| hook-5 | BellswapHook | P2 | open, disclosed, unfixed in the deployed code |
| hook-6 | BellswapHook | P3 | open, disclosed, unfixed in the deployed code |
| reference-1 | ReferenceFeed | P2 | open, disclosed, unfixed in the deployed code |
| reference-3 | ReferenceFeed | P2 | open, disclosed, unfixed in the deployed code |
| reference-4 | ReferenceFeed (with BellswapRelay) | P3 | open, disclosed, unfixed in the deployed code; does not apply to the live feed, which is past round 1 |
| mint-1 | BellMarket and BellMarketV2 | P2 | open, disclosed, unfixed in the deployed code of bsX0, bsX1 and TANKR |

#### hook-1: empty-pool price can be moved for free

- Location: bellswap-contracts `src/hook/BellswapHook.sol:244-255` (`_checkInitPrice`, called only from `createPool` :156 and `createSyntheticPool` :168).
- Description: the start-price band is enforced only at pool creation, so a pool with no in-range liquidity can be moved far from the reference at no cost, and a first liquidity provider then deposits at that price.
- Severity: P2.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: revert a swap in a pool with zero active liquidity unless its price limit is within the start band of a fresh reference, or check the spot price against that band in a `beforeAddLiquidity` hook.

#### hook-5: fee read only at the pre-swap and block-start price

- Location: bellswap-contracts `src/hook/BellswapHook.sol:385` (`_quote`; prices at :396, fee at :397, gap fee at :451-455).
- Description: the fee is priced from the pool price before the swap and the price recorded at block start (the higher of the two fees, :398), never from the executed path, so a swap whose pre-swap price and block-start reading are both near the reference pays the base fee for its whole move, including the part beyond the band or past the reference.
- Severity: P2.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: compute the fee from the executed swap path, for example by splitting the quote at the band edge or pricing at the worse of the start price and the reachable price limit.

#### hook-6: block-start price can be set deliberately

- Location: bellswap-contracts `src/hook/BellswapHook.sol:336` (block-start record in `_beforeSwap` :326, applied in `_quote` :398 and `_prices` :431-434).
- Description: the price recorded before the first swap of each parent-chain block can be displaced on purpose, so later swaps in that block without a tight price limit pay up to the maximum fee.
- Severity: P3.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: key the start price per transaction in transient storage instead of per parent-chain block.

#### reference-1: epoch roll during a pending episode erases the discontinuity evidence

- Location: bellswap-contracts `src/reference/l2/ReferenceFeed.sol:319-322` (epoch roll in `push` :269), with `_evaluate` :425 and `_promoteIfDue` :476-481.
- Description: an epoch roll while a round is pending replaces the anchor that made the episode qualify, so the move is not recorded as a discontinuity and a market can miss its settlement trigger.
- Severity: P2.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: before replacing `anchorPrice` while `pendingRound != 0`, fold the pending round's move from the old anchor into `maxPendingMoveBps`.

#### reference-3: late correction cannot revert a promotion

- Location: bellswap-contracts `src/reference/l2/ReferenceFeed.sol:456-465` (`_endHoldIfDue`, run in `_lazy` :450 before the revert branch of `_evaluate` at :394).
- Description: once the promotion hold has ended on chain, a correcting report that was read inside the hold but delivered late can no longer revert the promoted price.
- Severity: P2.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: in `_evaluate`, also take the revert branch when the report's `l1Timestamp` is at or before `holdUntil` and its price is within the jump threshold of the pre-jump round.

#### reference-4: a held relay ticket can become round 1 of a new feed

- Location: bellswap-contracts `src/reference/l2/ReferenceFeed.sol:386-392` (first-round branch of `_evaluate`), with `push` :312 and `src/reference/l1/BellswapRelay.sol:287-308`.
- Description: a relay ticket kept unredeemed can later deliver old source data as the first, immediately confirmed round of a newly created feed; the live feed `0xA8Dd192FFcAcC451D104BEEB628190ab4D3aA6ad` is past round 1, so this applies only to feeds created later.
- Severity: P3.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: while a feed has no confirmed round, ignore reports whose `l1Timestamp` is older than `DELIVERY_LAG_LIMIT` or than the feed's creation time.

#### mint-1: global settlement trigger counts collateral that never reaches the holders' pool

- Location: BellMarket, bellswap-contracts `src/mint/BellMarket.sol:548-552` (`_globalCondition`, used at :285 and :412); BellMarketV2, bellswap-markets `src/mint/BellMarketV2.sol:556-560` (used at :293 and :420).
- Description: the trigger compares all collateral, including debt-free collateral and surplus that settlement returns to minters, with the debt, so a market can stay live while the collateral that would back its token holders is below the settlement threshold.
- Severity: P2, in BellMarket (bsX0, bsX1) and in BellMarketV2 (TANKR).
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: base the trigger on the collateral that would enter the settlement pool, the sum of `min(C_i, ceil(V(D_i, P)))`, against the value of total supply times `SETTLE_GCR_BPS`.

### 6.2 Further findings of the 2 October review

All P3. Three votes confirmed each of them, except reference-6, hook-2 and mint-2, which two votes confirmed. Line numbers as in 6.1.

| id | Contract and location | Issue | BellMarketV2 (TANKR) |
|---|---|---|---|
| reference-2 | GuardedFeedView `latestRoundData` (`src/reference/l2/GuardedFeedView.sol:53`) | Returns `confirmed()`, which is the promoted round from promotion on, through the 24 h promotion hold, while a correction can still revert the promotion. The markets price the pre-jump round during the hold (`src/mint/BellMarket.sol:485-487`). Both deployed hook pools read this view (section 1.5). | publishes the same view as `REFERENCE_VIEW` (mint-2), but prices positions from the feed with its own hold handling (`src/mint/BellMarketV2.sol:491-496`), like BellMarket; the TANKR pool reads the view (hook-2) |
| reference-5 | ReferenceFeed pending restart (`src/reference/l2/ReferenceFeed.sol:426-433`) | A restart of the pending clock drops the moves of the discarded chain, so the recorded maximum pending move can understate the episode's total move and a discontinuity above `DISCONTINUITY_BPS` can go unrecorded. | reads the same feed |
| reference-6 | ReferenceFeed `push` (`ReferenceFeed.sol:276`) | A strictly newer `observedAt` is accepted even when its `(l1Block, seq)` read key is older. Reachable only on kind 2 (aggregator) feeds; the deployed feed is kind 1. | not affected |
| reference-7 | GuardedFeedView `_face` (`GuardedFeedView.sol:84-90`) and hook `_readFeed` | The relayed `maxTimeDelay` is stored, but no age check uses it: the deployed view has `MAX_AGE` 0 and both pools use `staleAfter` 194,400 s, so a price that the source's own `maxTimeDelay` would reject is still read as fresh. | not affected (markets use `MINT_MAX_AGE` and `LIQ_MAX_AGE`) |
| hook-2 | BellswapHook `_readFeed` (`src/hook/BellswapHook.sol:498`) | The swap anchor reads only `latestRoundData` and never `hold()`, so during a promotion hold it follows the promoted round (same cause as reference-2). | the TANKR pool uses the same hook and view |
| hook-4 | BellswapHook `_declaresReference` (`BellswapHook.sol:286-289`, used by `createPool` at :161) | A token counts as synthetic when a staticcall of `referenceFeed()` from the hook returns a nonzero word. A token can answer the hook differently from other callers, so the generic or synthetic classification is not reliable; a token whose fallback answers unknown selectors can get no pool. | not affected |
| hook-7 | BellswapHook `_create` (`BellswapHook.sol:214`) | The first `createPool` for a PoolKey fixes the feed and fee configuration of that PoolId for good, so the key of a non-referenced pair can be taken first with a hostile feed and `maxFee` (one key per tickSpacing). Synthetic keys fully determine their configuration. | not affected |
| mint-2 | BellMarket constructor (`src/mint/BellMarket.sol:88`) | The published `REFERENCE_VIEW` is `viewOf(feed, 0)`, the view of reference-2, which does not apply the hold that the market itself applies. | same at `src/mint/BellMarketV2.sol:96` |
| mint-3 | BellMarket `close` (`BellMarket.sol:205`) | `close` (and repay followed by `withdraw`) reads no price and stays callable until someone calls `triggerSettlement`, so in the block in which the global condition becomes true a minter can take all its collateral out before the trigger, and that collateral never enters the holders' pool. | same `close` at `BellMarketV2.sol:213` |
| mint-4 | BellMarket `open` (`BellMarket.sol:138`) | `open` appends a position on every call, and `withdraw` returns all collateral without a price read when the debt is 0, so empty positions can be created without bound for gas only. Nothing iterates on chain; off-chain scans of all positions slow down. | same at `BellMarketV2.sol:146` and :175 |

### 6.3 Residual paths of the TANKR tier

The review rounds of the V2 and V3 code (section 9) measured four paths in which a TANKR position at the 150 percent liquidation ratio becomes insolvent before anyone can liquidate it, and one property of the global trigger that removes a backstop from those paths. All five were kept: removing the hold-end report, the late delivery burst or the stale stack needs a ReferenceFeed change or new market code; the hold stack is addressed operationally, with no contract change; the global trigger has no small fix. Debt that a liquidation books as bad debt adds no collateral to the settlement pool, but its tokens stay in the supply and redeem pro rata like every other token (`src/mint/BellMarketV2.sol:247-253`, :337-344, :567-571), so bad debt falls pro rata on every holder of the market's token. The review rounds gave these paths no severity rating.

#### Hold-end report

- Location: bellswap-contracts `src/reference/l2/ReferenceFeed.sol:456-465` (hold end), :319-322 (epoch roll) and :412 (direct confirmation).
- Description: the `push` that ends a promotion hold can also roll the epoch anchor and confirm a further move, so the market price can move with no block in which liquidation is possible.
- Severity: not rated; kept as a residual path.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: do not confirm a direct move in a `push` that ends a hold (feed change), or open liquidation at the promoted price shortly before `holdUntil` (new market code).

#### Late delivery burst

- Location: bellswap-contracts `src/reference/l2/ReferenceFeed.sol:312` (`lastLateReceivedAt`); bellswap-markets `src/mint/BellMarketV2.sol:505` and :523 (`LAG_GRACE` in `liqOk`).
- Description: a round delivered late closes liquidation and the global trigger for `LAG_GRACE` 7,200 s, while confirmations and an epoch roll can still move the price.
- Severity: not rated; kept as a residual path.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: in new market code, drop the `LAG_GRACE` closure of liquidation or bypass it for positions far below the liquidation ratio.

#### Stale stack

- Location: bellswap-markets `src/mint/BellMarketV2.sol:523` (`LIQ_MAX_AGE` in `liqOk`); bellswap-contracts `src/reference/l2/ReferenceFeed.sol:319-322` (epoch roll).
- Description: while the source age is above `LIQ_MAX_AGE` 259,200 s, liquidation and the global trigger are off, yet the feed can still confirm one epoch roll at a time, so liquidation reopens at a price that has moved with no fixed bound. Only the reference source can open this path: the relay reads the source in the same transaction and no caller chooses a price or timestamp (`src/reference/l1/BellswapRelay.sol:11-15`, :169-185), so the source itself would have to publish such rounds. This is the trust class of reference source trust (section 6.4); whether the source can publish them at all is not verified.
- Severity: not rated; kept as a residual path.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: ignore a round whose observation time trails its L1 timestamp by more than a bound (feed change; an honest observation relayed after a long relay outage would then be dropped), or run the markets' liquidation age check on the round's receive time instead of its observation time (new market code; it would allow liquidation on a days-old observation when a relay catches up). Kept as disclosed on mainnet as a source-trust path.

#### Hold stack beyond liquidator inventory

- Location: bellswap-contracts `src/reference/l2/ReferenceFeed.sol:456-465` (hold end) and :467 (`_promoteIfDue`); bellswap-markets `src/mint/BellMarketV2.sol:518` (minting closed while a round is pending or held).
- Description: a pending round set during a hold promotes at hold end and starts a new hold, so the price steps twice while minting is closed and liquidators can repay only with tokens they already hold.
- Severity: not rated; kept as a residual path.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: liquidators mint a token inventory when the market opens, before positions open, and keep it at the larger of the restore need after one price step and a fixed reserve; each further step in a stack needs one more step of inventory (operational, no contract change).

#### Global trigger is not an insolvency backstop

- Location: bellswap-markets `src/mint/BellMarketV2.sol:556-560` (`_globalCondition`).
- Description: the trigger sums all collateral, including surplus that settlement returns to its owner, so positions can be insolvent while the aggregate stays above `SETTLE_GCR_BPS` (same cause as mint-1). Not a loss path by itself; it removes a backstop from the four paths above.
- Severity: not rated; kept as a residual path.
- Status: open, disclosed, unfixed in the deployed code.
- Suggested fix: base the trigger on the collateral each position would contribute to the settlement pool, as for mint-1.

### 6.4 Accepted residual risks of the design

The Bellswap specification lists these as accepted residual risks in its threat model (section 9 of the specification). Several match findings above.

- Reference source trust: a wrong source price within 20 percent of both the confirmed price and the epoch anchor is confirmed at once; stepping moves the confirmed price at most 20 percent from the anchor per epoch, and at most 1.44 times within minutes across one epoch boundary; a wrong price left uncorrected for 6 h is promoted and used by the markets after the 24 h hold. The specification states that the loss is bounded per market by its cap. `CAP_USD` limits only the value of the supply at minting (`src/mint/BellMarket.sol:531`, `src/mint/BellMarketV2.sol:538-539`), so it bounds the debt issued, not the loss in USD: a later price rise raises the value of that debt, and the liquidation of an insolvent position seizes all its collateral (`src/mint/MarketMath.sol:106-112`), which the cap does not limit. The stale stack (6.3) belongs to this trust class and has no fixed bound. Whether the source corrects a wrong price within 6 h, or at all on weekends, is not verified.
- Late correction: a correction delayed more than the 24 h promotion hold past `promotableAt` no longer reverts a promotion (reference-3).
- Sequencer outage: `ARM_DELAY` narrows the stale-settlement race but does not close it; after a long sequencer outage, stale settlement can be triggered before the relay backlog is sequenced. A late-delivered relay report closes liquidation for the 2 h `LAG_GRACE`, at most once per new source observation.
- Broken feed: a failing feed makes a pool expensive (the fee fails closed to `maxFee`, at most 10 percent), not unusable.
- PoolKey squatting of non-referenced pairs, one key per tickSpacing (hook-7).
- Liquidation can stall when minting is closed and the pool is thin; bad debt then dilutes the token holders.
- USDG: a freeze or blacklist of a market address locks that market (no exit, no liquidation, no payout).
- Hook block-start rule (hook-5, hook-6): the fee is set from the pre-swap price and the price recorded at the start of the parent-chain block, not from the executed swap path, so the fee a swap pays can be lower or higher than its executed move would warrant.
- Feed clock restart (reference-5).

The specification is not public; the reviewing firm can request it, together with the private test suite, at hi@bellswap.fun.

## 7. Tests

bellswap-contracts contains no tests. bellswap-markets contains the market tests under `test/mint/` (29 files, 20 `.t.sol`, 169 test functions, 2 invariant functions; 35 suites, 328 passing, see section 3). The full suite, including the hook, reference, spec, review and integration tests, is in the private development repository at commit 37b342e; access for the reviewing firm: hi@bellswap.fun.

Counts at 37b342e, per directory under `test/` (`function test` and `function invariant` occurrences in source; "fuzzed" counts test functions with at least one parameter, which forge fuzzes):

| Directory | .sol files | .t.sol files | test functions | invariant functions | fuzzed |
|---|---|---|---|---|---|
| harness | 19 | 5 | 249 | 0 | 1 |
| hook | 4 | 3 | 72 | 0 | 22 |
| integration | 4 | 4 | 28 | 0 | 0 |
| mint | 36 | 27 | 288 | 2 | 10 |
| mocks | 1 | 1 | 3 | 0 | 0 |
| reference | 11 | 9 | 178 | 0 | 16 |
| review | 58 | 56 | 161 | 0 | 2 |
| script | 13 | 12 | 87 | 0 | 1 |
| spec | 31 | 24 | 511 | 2 | 27 |
| **total** | **177** | **141** | **1,577** | **4** | **79** |

`forge test --summary --offline` at 37b342e (8 October 2026, default profile): 170 suites, 1,497 passed, 0 failed, 249 skipped, exit 0. The 249 skipped tests are the nine harness suites under `test/harness/`, which run only under `FOUNDRY_PROFILE=harness`. forge's pass count is higher than the function count because tests inherited from an abstract base run once per derived suite.

Fuzz and invariant tests:

- 79 fuzzed test functions: 76 named `testFuzz_*` and 3 `test_*` functions with parameters. Default fuzz runs: 256 (`[profile.default.fuzz]`).
- 4 invariant functions: `test/mint/invariant/MintInvariants.t.sol:60` `invariant_M3_M4_M13_M14_M8` and :112 `invariant_M15_processingLiveness`; `test/spec/c4/C4InvariantSpec.t.sol:200` `invariant_M3_M4_M13` and :216 `invariant_M11_balancesMatchCollateral`. In the default pass they run as 10 invariant tests in five suites: C4InvariantSpec at 64 runs (depth 100), MintInvariantsTest at 128 runs (depth 250), and three suites that inherit the two Mint invariants and run against BellMarketV2 at 256 runs (depth 500): MintInvariantsV2Test (a V2 factory market, `test/mint/v2/MarketSuitesV2.t.sol`), MintInvariantsOnV3Test (a V3 factory market) and MintInvariantsTL1Test (the second market at the TANKR tier), both in `test/mint/v3/MarketSuitesV3.t.sol` (:68, :82). The inherited suites do not pick up the inline `forge-config` lines of MintInvariantsTest.
- Invariant profile in the private repository: `[profile.invariant.invariant]` (`foundry.toml:80-82` at 37b342e) sets `runs = 10000`, `depth = 500`. The inline settings of MintInvariantsTest and C4InvariantSpec keep 10,000 runs and set the depth to 250 and 100; the three inherited suites take the profile values. In bellswap-markets, `[profile.invariant]` only names its artifact and cache folders (so that the inline lines parse): there only MintInvariantsTest runs 10,000 runs (depth 250), and the three inherited suites, which test BellMarketV2, stay at the default 256 runs (depth 500). Run with `FOUNDRY_PROFILE=invariant forge test --match-test '^invariant'`. A full 10,000-run pass has not been run in either repository.

How to run (in bellswap-markets, or in the private repository for the full suite):

```
bash tools/install-deps.sh
forge test                                                   # default profile
FOUNDRY_PROFILE=invariant forge test --match-test '^invariant'  # 10,000 runs per invariant in the private repository only (see above)
```

The harness suites under `test/harness/` (private repository only) run under `FOUNDRY_PROFILE=harness`.

## 8. Coverage

Measured on 8 October 2026 with forge 1.7.1 in the private development repository at commit 37b342e, whose `src/` files equal those in both public repositories:

```
forge coverage --skip QuorumSessionAnchor.t.sol --skip QuorumSessionAnchorRearm.t.sol \
  --report summary --report lcov --report-file lcov.info
```

`forge coverage` builds without the optimizer and without via-IR. The two skipped files test code that is not in either public repository and not in scope; without the skip the coverage build fails with "Stack too deep" in one of them, also with `--ir-minimum`. The run compiled 343 of 345 files and ran 168 suites: 1,429 passed, 3 failed, 249 skipped. The 3 failures are size and gas bounds that the unoptimized coverage build exceeds (`BellMarketFactoryV2.t.sol` `test_constructor_largestMenuFitsInitCodeLimit` and `test_marketCodeIsBellMarketV2DataOnly`, `ReferenceFeedFactory.t.sol` `test_gas_reportAgainstMinL2Gas`); the optimized `forge test` at the same commit passes all three (0 failed, section 7). Interface-only files have no executable lines and do not appear.

| File | Lines | Statements | Branches | Functions |
|---|---|---|---|---|
| src/hook/BaseHook.sol | 91.49% (43/47) | 94.29% (33/35) | 100.00% (1/1) | 91.30% (21/23) |
| src/hook/BellswapHook.sol | 100.00% (198/198) | 98.91% (273/276) | 92.86% (39/42) | 100.00% (39/39) |
| src/mint/BellMarket.sol | 100.00% (313/313) | 100.00% (401/401) | 100.00% (72/72) | 100.00% (39/39) |
| src/mint/BellMarketFactory.sol | 96.39% (80/83) | 97.58% (121/124) | 91.30% (21/23) | 100.00% (12/12) |
| src/mint/BellMarketFactoryV2.sol | 97.89% (139/142) | 98.76% (239/242) | 95.24% (40/42) | 100.00% (20/20) |
| src/mint/BellMarketFactoryV3.sol | 96.50% (138/143) | 84.96% (209/246) | 16.28% (7/43) | 100.00% (20/20) |
| src/mint/BellMarketV2.sol | 100.00% (311/311) | 100.00% (399/399) | 100.00% (72/72) | 100.00% (39/39) |
| src/mint/MarketMath.sol | 100.00% (53/53) | 94.12% (80/85) | 70.00% (7/10) | 100.00% (9/9) |
| src/reference/l1/BellTypes.sol | 100.00% (2/2) | 100.00% (2/2) | 100.00% (0/0) | 100.00% (1/1) |
| src/reference/l1/BellswapRelay.sol | 100.00% (112/112) | 100.00% (159/159) | 100.00% (18/18) | 100.00% (24/24) |
| src/reference/l2/GuardedFeedView.sol | 100.00% (31/31) | 100.00% (38/38) | 100.00% (3/3) | 100.00% (9/9) |
| src/reference/l2/ReferenceDescription.sol | 100.00% (2/2) | 100.00% (2/2) | 100.00% (0/0) | 100.00% (1/1) |
| src/reference/l2/ReferenceFeed.sol | 100.00% (244/244) | 99.66% (297/298) | 97.78% (44/45) | 100.00% (43/43) |
| src/reference/l2/ReferenceFeedFactory.sol | 100.00% (74/74) | 100.00% (84/84) | 100.00% (20/20) | 100.00% (13/13) |
| **Total, 14 files** | **99.15% (1740/1755)** | **97.74% (2337/2391)** | **87.98% (344/391)** | **99.32% (290/292)** |

The totals are the sums of the 14 rows. forge's own total over every compiled file (tests, mocks and libraries included) is 30.73% lines and is not a scope figure.

Gaps worth the reviewer's attention:

- `src/mint/BellMarketFactoryV3.sol`, branches 16.28% (7/43). Most of the 36 untaken branches are revert paths no V3 test reaches: menu and label length (lines 108, 113), first market id (118), non-canonical feed (132), unknown tier (181), the `PriceNotUsable` catch (248-249), tier fields 4 to 8 (271-275) and the label checks (281-290, 310-334).
- `src/mint/MarketMath.sol`, branches 70.00% (7/10): untaken at lines 43, 67 and 86.
- Uncovered lines: `BaseHook.sol` 62, 63, 172, 177 (default reverts of `_beforeInitialize` and `_beforeSwap`, never called); `BellMarketFactory.sol` 87-89 and `BellMarketFactoryV2.sol` 139-141 (assembly revert bubbling); `BellMarketFactoryV3.sol` 151-153, 248, 249.
- Other untaken branches: `BellswapHook.sol` 458, 459 (fee clamps), 487 (`anchor == 0`); `BellMarketFactory.sol` 86, 138; `BellMarketFactoryV2.sol` 138, 208; `ReferenceFeed.sol` 478.

## 9. Prior review

On 2 October 2026 the reviewed commit (private 95c610d, the same `src/` tree as bellswap-contracts `72f7225`) went through an internal review run by the Bellswap team: per area, four automated reviewer slots using large language models from three vendors, a merge step, then three verifier passes per finding (refute, reproduce, impact), and a final verdict. Its confirmed findings in in-scope contracts are listed in sections 6.1 (seven findings) and 6.2 (ten findings); all are open. 95c610d contains no V2 or V3 code.

BellMarketV2 and BellMarketFactoryV2 (5 and 6 October 2026, committed as private b7ab0b0) and BellMarketFactoryV3 with the TANKR tier (6 and 7 October 2026, private e144e43) went through separate internal review rounds with large language models before deployment: for V2 a plan review, a diff review by two automated reviewers and a polish round; for V3 diff, whole-file and fix-check rounds, three verifier passes per finding and a final verdict per finding. Their findings against the contracts are the TANKR-tier residual paths in section 6.3, which were kept; the other findings they confirmed concerned deploy scripts and tests (out of scope). One of those is open: the label check of the deploy scripts (`script/lib/LabelLint.sol`) lets a symbol pass when text surrounds a banned word on both sides. The V2 and V3 `src/` files are unchanged from those commits to 37b342e.

These reviews were run by the Bellswap team. They are not an audit and not an independent review by a security firm.

## 10. Documentation

- bellswap-contracts `README.md`: "Deployed on mainnet" (addresses and the bsX0 pool), "Source of record" (private commit 95c610d, `src/` tree hash), "Build", "License". `NOTICE`: third-party code and its origin.
- bellswap-markets `README.md`: "Where the live code is", "Contents" (each file's role), "Deployments" (Robinhood Chain testnet and mainnet addresses and transactions).
- NatSpec in the source. Comments cite sections of the Bellswap specification (for example "SPEC 8.5"). The specification is not public; the reviewing firm can request it at hi@bellswap.fun (section 6.4).

## 11. Contact

hi@bellswap.fun

## 12. Freeze

The scope is frozen at the tag `audit-2026-10-14` in each repository. Each tag points to exactly one commit: in bellswap-contracts the commit that adds this document, in bellswap-markets the commit that adds its scope note. The two tag commits are the snapshot of the review; the engagement letter names both.

| Tag | Repository | Commit | Check |
|---|---|---|---|
| `audit-2026-10-14` | bellswap-contracts | the commit that adds this document on top of `72f72258bebcf7679a3d29a202a9a342530e54ca` (main on 8 October 2026) | `git diff --name-only 72f72258bebcf7679a3d29a202a9a342530e54ca audit-2026-10-14` lists only `AUDIT-SCOPE.md` and `README.md`; `git rev-parse audit-2026-10-14:src` prints `31f74163bca3af1cfee05a77bb0f4b4ec2ecdf8f` |
| `audit-2026-10-14` | bellswap-markets | the commit that adds its scope note `AUDIT-SCOPE.md`, a descendant of the commit tagged `tankr-mainnet-2026-10-07` (`ef1039e9877948457ca090347f67823b3fcbfee8`) | `git diff --name-only ef1039e9877948457ca090347f67823b3fcbfee8 audit-2026-10-14` lists only `AUDIT-SCOPE.md`; `git rev-parse audit-2026-10-14:src` prints `6764f1b26786ca189cf898bb719c06c0d24315fa` |

Both checks together pin the whole tree: source, tests, scripts, build configuration and dependency installer are those of the named base commit, and only the documentation files named in the check differ (two in bellswap-contracts, one in bellswap-markets).
