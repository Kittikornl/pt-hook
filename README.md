**PTHOOK: Pendle Yield Booster Hook**
:Supercharging Uniswap V4 Liquidity with Pendle's Yield-Bearing Tokens


**Project Description:**

The Pendle Yield Booster Hook is designed to enhance yield opportunities for liquidity providers (LPs) on Uniswap V4. By integrating with Pendle Finance, a leading decentralized finance (DeFi) protocol specializing in yield tokenization, the hook enables LPs to earn additional yield through Pendle's PT (Principal Tokens).


**Problem:**

Current Uniswap V4 liquidity providers rely solely on swap fees for their income, missing out on the potential for greater yield generation offered by other DeFi protocols. This can lead to liquidity fragmentation and decreased competitiveness for Uniswap.


**Solution:**

The Pendle Yield Booster Hook addresses this issue by seamlessly integrating Pendle Finance's PT tokens into Uniswap V4 pools. The hook automatically utilizes a portion of collected swap fees to purchase PT tokens, which generate yield over time. When LPs withdraw their liquidity, the accrued yield from PT tokens is distributed alongside their original deposit and swap fee earnings, significantly boosting their overall returns.


**Key Benefits:**

- **Higher APY for LPs:** Significantly increases yield potential compared to standard Uniswap V4 pools, incentivizing greater liquidity provision.
- **Enhanced Liquidity for Uniswap:** Attracts and retains liquidity, ensuring a vibrant and competitive marketplace for traders.
- **Innovative DeFi Integration:** Demonstrates a novel approach to combining the strengths of two leading DeFi protocols (Uniswap and Pendle Finance) to create a synergistic product.


**Technical Implementation Timeline:**

1. **Handle buying/selling of PT** tokens using swap fees, integrating with Pendle Finance, and establish basic fee collection within the pool.
2. **Handle native**
3. **Token Supports** Swap fee to buy other token which Pendle support (eg. ETH to by weETH to access pendle pool).


**Potential Impact:**

The Pendle Yield Booster Hook has the potential to transform the Uniswap V4 landscape by offering LPs a more attractive yield-generating opportunity. This could lead to increased liquidity, reduced slippage for traders, and a stronger competitive position for Uniswap in the evolving DeFi ecosystem.


## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test -vv
```

### Format

```shell
$ forge fmt
```


**Team:**

- Product Owner: Pshato0x (Putt Sirisaksopit): EIR & Venture at Symmetry, Co-founder of GovernX Labs (g[x])
- Lead Development: Slippopz (Kittikorn Leelawanich): Senior Blockchain Engineer at Init Capital
