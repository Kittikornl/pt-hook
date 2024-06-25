// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks, IHooks} from "v4-core/libraries/Hooks.sol";
import {BalanceDeltaLibrary, BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {CurrencyDelta} from "v4-core/libraries/CurrencyDelta.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";
import {Position} from "v4-core/libraries/Position.sol";
import {ProtocolFeeLibrary} from "v4-core/libraries/ProtocolFeeLibrary.sol";
import {FixedPoint128} from "v4-core/libraries/FixedPoint128.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {IPtHook} from "pt-hook/interfaces/IPtHook.sol";
import {IPendleRouter, ApproxParams} from "pt-hook/interfaces/IPendleRouter.sol";
import {IPendleSyToken} from "pt-hook/interfaces/IPendleSyToken.sol";
import {IPendleMarket} from "pt-hook/interfaces/IPendleMarket.sol";

contract PtHook is BaseHook, Ownable, IPtHook {
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyDelta for Currency;
    using TransientStateLibrary for IPoolManager;

    using FullMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int128;
    using SafeCast for int256;
    using SafeERC20 for IERC20;

    mapping(PoolId => MarketInfo) private _marketInfos;

    address public pendleRouter;

    BalanceDelta private _tempFee; // fee to be realized in afterRemoveLiquidity
    BalanceDelta private _tempRealizeFee; // realized fee to be transfered in afterRemoveLiquidity

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) Ownable(msg.sender) {}

    /// @inheritdoc BaseHook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: true
        });
    }

    /// @inheritdoc BaseHook
    function afterInitialize(address sender, PoolKey calldata key, uint160, int24, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        require(sender == owner(), "PtHook: only owner can initialize");
        SetMarketParams memory params = abi.decode(hookData, (SetMarketParams));
        _setMarket(key, params);
        return this.afterInitialize.selector;
    }

    /// @dev sell pt before removing liquidity
    /// @param sender user address
    /// @param key pool key
    /// @param params liquidity params
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override returns (bytes4) {
        PoolId poolId = key.toId();
        // calculate all user's trading fees
        uint256 realizedFee0;
        uint256 realizedFee1;
        MarketInfo memory marketInfo = _marketInfos[poolId];
        (uint256 feeOwned0, uint256 feeOwned1) = _getUserTradingFee(sender, poolId, params);
        feeOwned0 = feeOwned0 < marketInfo.totalFee0 ? feeOwned0 : marketInfo.totalFee0;
        feeOwned1 = feeOwned1 < marketInfo.totalFee1 ? feeOwned1 : marketInfo.totalFee1;
        // calculate ptAmount to be sold
        if (marketInfo.market0 != address(0)) {
            uint256 ptAmount0 = feeOwned0 * marketInfo.totalPt0 / marketInfo.totalFee0;
            if (ptAmount0 > 0) {
                realizedFee0 = _sellPt(poolId, marketInfo.market0, ptAmount0, Currency.unwrap(key.currency0));
            }
            marketInfo.totalFee0 -= feeOwned0.toUint128();
            marketInfo.totalPt0 -= realizedFee0.toUint128();
            emit RealizeFee(poolId, marketInfo.market0, feeOwned0, realizedFee0);
        }
        if (marketInfo.market1 != address(0)) {
            uint256 ptAmount1 = feeOwned1 * marketInfo.totalPt1 / marketInfo.totalFee1;
            if (ptAmount1 > 0) {
                realizedFee1 = _sellPt(poolId, marketInfo.market1, ptAmount1, Currency.unwrap(key.currency1));
            }
            marketInfo.totalFee1 -= feeOwned1.toUint128();
            marketInfo.totalPt1 -= realizedFee1.toUint128();
            emit RealizeFee(poolId, marketInfo.market1, feeOwned1, realizedFee1);
        }
        // update marketInfo
        _marketInfos[poolId] = marketInfo;
        // store user'trading fees and realized trading fee to be used in afterRemoveLiquidity
        _tempFee = toBalanceDelta(feeOwned0.toInt256().toInt128(), feeOwned1.toInt256().toInt128());
        _tempRealizeFee = toBalanceDelta(realizedFee0.toInt256().toInt128(), realizedFee1.toInt256().toInt128());
        return IHooks.beforeRemoveLiquidity.selector;
    }

    /// @dev update user's delta after removing liquidity to include realized trading fee
    /// @param key pool key
    function afterRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        BalanceDelta hookDelta;
        if (_tempRealizeFee == BalanceDeltaLibrary.ZERO_DELTA) return (IHooks.afterRemoveLiquidity.selector, hookDelta);
        // load user's realized trading fee
        BalanceDelta tempRealizeFee = _tempRealizeFee;
        hookDelta = tempRealizeFee - _tempFee;
        hookDelta = toBalanceDelta(-hookDelta.amount0(), -hookDelta.amount1());
        uint256 amount0;
        uint256 amount1;
        // note: take amount from poolManager to avoid revert
        // todo: need to refactor this part for cleaner code
        if (hookDelta.amount0() > 0) {
            amount0 = int256(hookDelta.amount0()).toUint256();
            poolManager.take(key.currency0, address(this), amount0);
        }
        if (hookDelta.amount1() > 0) {
            amount1 = int256(hookDelta.amount1()).toUint256();
            poolManager.take(key.currency1, address(this), amount1);
        }
        // clear user state
        _tempFee = BalanceDeltaLibrary.ZERO_DELTA;
        _tempRealizeFee = BalanceDeltaLibrary.ZERO_DELTA;
        // transfer realized trading fee to pool
        amount0 += int256(tempRealizeFee.amount0()).toUint256();
        amount1 += int256(tempRealizeFee.amount1()).toUint256();
        // todo: need to refactor this part for cleaner code
        if (amount0 > 0) {
            poolManager.sync(key.currency0);
            key.currency0.transfer(address(poolManager), amount0);
            if (hookDelta.amount0() < 0) {
                int256 delta = poolManager.currencyDelta(address(this), key.currency0);
                poolManager.settle(key.currency0);
                delta = poolManager.currencyDelta(address(this), key.currency0);
                delta += hookDelta.amount0();
                if (delta > 0) {
                    poolManager.take(key.currency0, address(this), delta.toUint256());
                    key.currency0.transfer(address(poolManager), delta.toUint256());
                }
            }
        }
        if (amount1 > 0) {
            poolManager.sync(key.currency1);
            key.currency1.transfer(address(poolManager), amount1);
            if (hookDelta.amount1() < 0) {
                poolManager.settle(key.currency1);
                int256 delta = poolManager.currencyDelta(address(this), key.currency1);
                delta += hookDelta.amount1();
                if (delta > 0) {
                    poolManager.take(key.currency1, address(this), delta.toUint256());
                    key.currency1.transfer(address(poolManager), delta.toUint256());
                }
            }
        }
        return (IHooks.afterRemoveLiquidity.selector, hookDelta);
    }

    /// @dev using trading fee to buy pt
    /// @param key pool key
    /// @param swapParams swap params
    /// @param swapDelta swap delta
    /// @param hookData extra data for buying pt
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta swapDelta,
        bytes calldata hookData
    ) external override returns (bytes4, int128) {
        PoolId poolId = key.toId();
        MarketInfo storage marketInfo = _marketInfos[poolId];
        address market;
        uint256 swapAmount;
        Currency currency;
        {
            market = swapParams.zeroForOne ? marketInfo.market0 : marketInfo.market1;
            swapAmount = int256((swapParams.zeroForOne ? swapDelta.amount0() : swapDelta.amount1()) * -1).toUint256();
            currency = swapParams.zeroForOne ? key.currency0 : key.currency1;
        }
        // check if pt is exist and market is not expired
        if (market != address(0)) {
            if (!IPendleMarket(market).isExpired()) {
                // note: 1.since hook provides all address, we can ignore check-update-interaction pattern here
                //       2.swapper can do a sandwich attack to avoid pool's trading fee
                require(hookData.length != 0, "PtHook: missing hook data for buying pt");
                {
                    (,,, uint16 observationIndex,,) = IPendleMarket(market)._storage();
                    (uint32 lastTradeTimestamp,,) = IPendleMarket(market).observations(observationIndex);
                    require(lastTradeTimestamp < block.timestamp, "PtHook: last trade is too close");
                }
                // calculate trading fee
                uint256 fee;
                {
                    (,, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(poolId);
                    fee = swapAmount.mulDivRoundingUp(lpFee - protocolFee, ProtocolFeeLibrary.PIPS_DENOMINATOR);
                }
                // take trading fee from pool
                poolManager.take(currency, address(this), fee);
                // note: since swapper provide data for buying pt, this can lead to a sandwich attack
                // check market's last trade timestamp
                // buy pt need extra data for swapping
                ApproxParams memory guessPtOut = abi.decode(hookData, (ApproxParams));
                uint256 ptAmount = _buyPt(poolId, market, Currency.unwrap(currency), fee, guessPtOut);
                // update pt info
                if (swapParams.zeroForOne) {
                    marketInfo.totalFee0 += fee.toUint128();
                    marketInfo.totalPt0 += ptAmount.toUint128();
                } else {
                    marketInfo.totalFee1 += fee.toUint128();
                    marketInfo.totalPt1 += ptAmount.toUint128();
                }
                return (IHooks.afterSwap.selector, fee.toInt256().toInt128());
            }
        }
        // return hookDelta to avoid revert
        return (IHooks.afterSwap.selector, 0);
    }

    function setMarket(PoolKey calldata key, SetMarketParams calldata params) external onlyOwner {
        _setMarket(key, params);
    }

    function setPendleRouter(address router) external onlyOwner {
        pendleRouter = router;
        emit SetPendleRouter(router);
    }

    function getMarketInfo(PoolId id) external view returns (MarketInfo memory) {
        return _marketInfos[id];
    }

    /// @dev set market of provided pool key
    /// @param key pool key
    /// @param params market params
    function _setMarket(PoolKey calldata key, SetMarketParams memory params) internal {
        PoolId poolId = key.toId();
        MarketInfo memory marketInfo = _marketInfos[poolId];
        MarketInfo storage newMarketInfo = _marketInfos[poolId];
        if (marketInfo.market0 != params.market0) {
            newMarketInfo.market0 = params.market0;
            if (params.market0 == address(0)) newMarketInfo.totalFee0 = 0;
            // note: no need to change market if market0 is address(0) since all trading fee will be in poolManager
            if (marketInfo.market0 != address(0) && marketInfo.totalFee0 != 0) {
                uint256 newPtAmount = _changeMarket(
                    poolId,
                    marketInfo.market0,
                    params.market0,
                    Currency.unwrap(key.currency0),
                    marketInfo.totalPt0,
                    params.guessPtOut0
                );
                newMarketInfo.totalPt0 = newPtAmount.toUint128();
            }
        }
        if (marketInfo.market1 != params.market1) {
            newMarketInfo.market1 = params.market1;
            if (params.market1 == address(0)) newMarketInfo.totalFee1 = 0;
            // note: no need to change market if market1 is address(0) since all trading fee will be in poolManager
            if (marketInfo.market1 != address(0) && marketInfo.totalFee1 != 0) {
                uint256 newPtAmount = _changeMarket(
                    poolId,
                    marketInfo.market1,
                    params.market1,
                    Currency.unwrap(key.currency1),
                    marketInfo.totalPt1,
                    params.guessPtOut1
                );
                newMarketInfo.totalPt1 = newPtAmount.toUint128();
            }
        }
        emit SetMarket(poolId, params.market0, params.market1);
    }

    /// @dev sell old market's pt and buy new market's pt (if needed)
    /// @param poolId pool id
    /// @param market old market
    /// @param newMarket new market
    /// @param token token to be used for buying pt
    /// @param totalPt total pt to be sold
    /// @param guessPtOut guess pt out for buying pt
    function _changeMarket(
        PoolId poolId,
        address market,
        address newMarket,
        address token,
        uint256 totalPt,
        ApproxParams memory guessPtOut
    ) internal returns (uint256 newPtAmount) {
        // sell pt
        uint256 realizedFee = _sellPt(poolId, market, totalPt, token);
        if (newMarket != address(0)) {
            // buy pt
            newPtAmount = _buyPt(poolId, newMarket, token, realizedFee, guessPtOut);
        } else {
            // transfer all token to pool
            Currency.wrap(token).transfer(address(poolManager), realizedFee);
        }
    }

    function _buyPt(PoolId poolId, address market, address tokenIn, uint256 amountIn, ApproxParams memory guessPtOut)
        internal
        returns (uint256 netPtOut)
    {
        (address syToken,,) = IPendleMarket(market).readTokens();
        // mint sy
        IERC20(tokenIn).forceApprove(syToken, amountIn);
        uint256 syAmount = IPendleSyToken(syToken).deposit(address(this), tokenIn, amountIn, 0);
        // buy pt
        IERC20(syToken).forceApprove(pendleRouter, syAmount);
        (netPtOut,) = IPendleRouter(pendleRouter).swapExactSyForPt(address(this), market, syAmount, 0, guessPtOut);
        emit BuyPt(poolId, market, amountIn, netPtOut);
    }

    function _sellPt(PoolId poolId, address market, uint256 ptAmount, address tokenOut)
        internal
        returns (uint256 amountOut)
    {
        (address syToken, address ptToken,) = IPendleMarket(market).readTokens();
        // sell pt to sy
        IERC20(ptToken).forceApprove(pendleRouter, ptAmount);
        (uint256 netSyOut,) = IPendleRouter(pendleRouter).swapExactPtForSy(syToken, market, ptAmount, 0);
        // redeem sy to underlying token
        amountOut = IPendleSyToken(syToken).redeem(address(this), netSyOut, tokenOut, 0, true);
        emit SellPt(poolId, market, ptAmount, amountOut);
    }

    function _getUserTradingFee(address sender, PoolId poolId, IPoolManager.ModifyLiquidityParams calldata params)
        internal
        view
        returns (uint256 feesOwed0, uint256 feesOwed1)
    {
        // read fee getFeeGrowthInside from poolManager
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            poolManager.getFeeGrowthInside(poolId, params.tickLower, params.tickUpper);
        // get user position info
        Position.Info memory info =
            poolManager.getPosition(poolId, sender, params.tickLower, params.tickUpper, params.salt);
        // calculate trading fees
        unchecked {
            feesOwed0 = FullMath.mulDiv(
                feeGrowthInside0X128 - info.feeGrowthInside0LastX128, info.liquidity, FixedPoint128.Q128
            );
            feesOwed1 = FullMath.mulDiv(
                feeGrowthInside1X128 - info.feeGrowthInside1LastX128, info.liquidity, FixedPoint128.Q128
            );
        }
    }

    function getUserTradingFee(address user, PoolId poolId, IPoolManager.ModifyLiquidityParams calldata params)
        external
        view
        returns (uint256 feesOwed0, uint256 feesOwed1)
    {
        return _getUserTradingFee(user, poolId, params);
    }
}
