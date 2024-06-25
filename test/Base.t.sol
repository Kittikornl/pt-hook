// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Deployers, IPoolManager, PoolIdLibrary, PoolKey, BalanceDelta} from "v4-core-test/utils/Deployers.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

import {PtHook, IPtHook, ApproxParams} from "pt-hook/PtHook.sol";
import {IPendleMarket} from "pt-hook/interfaces/IPendleMarket.sol";

contract BaseTest is Test, Deployers {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;

    PtHook hook;

    IPoolManager.ModifyLiquidityParams public CLIAM_FEE_PARAMS =
        IPoolManager.ModifyLiquidityParams({tickLower: -12000, tickUpper: 12000, liquidityDelta: 0, salt: 0});

    function mintAndApproveCurrency(Currency token) public {
        // mint token
        deal(Currency.unwrap(token), address(this), 1e36);
        address[8] memory toApprove = [
            address(swapRouter),
            address(swapRouterNoChecks),
            address(modifyLiquidityRouter),
            address(modifyLiquidityNoChecks),
            address(donateRouter),
            address(takeRouter),
            address(claimsRouter),
            address(nestedActionRouter.executor())
        ];
        // approve all
        for (uint256 i = 0; i < toApprove.length; i++) {
            IERC20(Currency.unwrap(token)).forceApprove(toApprove[i], type(uint256).max);
        }
    }

    function swapZeroToOne(uint256 swapAmount) public {
        ApproxParams memory hookData = ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0,
            maxIteration: 256,
            eps: 100000000000000
        });
        (uint256 fee0Bf, uint256 fee1Bf) =
            hook.getUserTradingFee(address(modifyLiquidityRouter), key.toId(), LIQUIDITY_PARAMS);
        IPtHook.MarketInfo memory infoBf = hook.getMarketInfo(key.toId());
        swap(key, true, swapAmount.toInt256(), abi.encode(hookData));
        (uint256 fee0Af, uint256 fee1Af) =
            hook.getUserTradingFee(address(modifyLiquidityRouter), key.toId(), LIQUIDITY_PARAMS);
        IPtHook.MarketInfo memory infoAf = hook.getMarketInfo(key.toId());
        uint256 fee0Delta = fee0Af - fee0Bf;
        uint256 fee1Delta = fee1Af - fee1Bf;
        uint256 totalFee0Delta = infoAf.totalFee0 - infoBf.totalFee0;
        assertGt(fee0Delta, 0, "not enough fee0");
        assertEq(fee1Delta, 0, "fee1 not 0");
        if (infoAf.market0 != address(0)) {
            assertLe(totalFee0Delta - fee0Delta, 1, "wrong total fee0");
            (, address ptToken,) = IPendleMarket(infoAf.market0).readTokens();
            assertEq(IERC20(ptToken).balanceOf(address(hook)), infoAf.totalPt0, "wrong total pt0");
        }
        if (infoAf.market1 != address(0)) {
            assertEq(infoBf.totalFee1, infoAf.totalFee1, "wrong total fee1");
            (, address ptToken,) = IPendleMarket(infoAf.market1).readTokens();
            assertEq(IERC20(ptToken).balanceOf(address(hook)), infoAf.totalPt1, "wrong total pt1");
        }
    }

    function swapOneToZero(uint256 swapAmount) public {
        ApproxParams memory hookData = ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0,
            maxIteration: 256,
            eps: 100000000000000
        });
        (uint256 fee0Bf, uint256 fee1Bf) =
            hook.getUserTradingFee(address(modifyLiquidityRouter), key.toId(), LIQUIDITY_PARAMS);
        IPtHook.MarketInfo memory infoBf = hook.getMarketInfo(key.toId());
        swap(key, false, swapAmount.toInt256(), abi.encode(hookData));
        (uint256 fee0Af, uint256 fee1Af) =
            hook.getUserTradingFee(address(modifyLiquidityRouter), key.toId(), LIQUIDITY_PARAMS);
        IPtHook.MarketInfo memory infoAf = hook.getMarketInfo(key.toId());
        uint256 fee0Delta = fee0Af - fee0Bf;
        uint256 fee1Delta = fee1Af - fee1Bf;
        uint256 totalFee1Delta = infoAf.totalFee1 - infoBf.totalFee1;
        assertEq(fee0Delta, 0, "fee0 not 0");
        assertGt(fee1Delta, 0, "not enough fee1");
        if (infoAf.market0 != address(0)) {
            assertEq(infoBf.totalFee0, infoAf.totalFee0, "wrong total fee0");
            (, address ptToken,) = IPendleMarket(infoAf.market0).readTokens();
            assertEq(IERC20(ptToken).balanceOf(address(hook)), infoAf.totalPt0, "wrong total pt0");
        }
        if (infoAf.market1 != address(0)) {
            assertLe(totalFee1Delta - fee1Delta, 1, "wrong total fee1");
            (, address ptToken,) = IPendleMarket(infoAf.market1).readTokens();
            assertEq(IERC20(ptToken).balanceOf(address(hook)), infoAf.totalPt1, "wrong total pt1");
        }
    }
}
