// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Base.t.sol";

contract PtHookTest is BaseTest {
    using PoolIdLibrary for PoolKey;
    using SafeCast for int256;

    uint24 fee = 3000;
    address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address rseth = 0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7;

    address usdePendleMarket = 0x19588F29f9402Bb508007FeADd415c875Ee3f19F;
    address rsEthPendleMarket = 0x99184849E35D91Dd85f50993bBb03A42Fc0A6FE7;

    address router = 0x0000000001E4ef00d069e71d6bA041b0A16F7eA0;

    function setUp() public {
        // vm.createSelectFork("https://rpc.ankr.com/eth");
        vm.createSelectFork("http:127.0.0.1:8545");
        LIQUIDITY_PARAMS =
            IPoolManager.ModifyLiquidityParams({tickLower: -12000, tickUpper: 12000, liquidityDelta: 1e26, salt: 0});
        REMOVE_LIQUIDITY_PARAMS =
            IPoolManager.ModifyLiquidityParams({tickLower: -12000, tickUpper: 12000, liquidityDelta: -1e26, salt: 0});

        deployFreshManagerAndRouters();

        currency0 = Currency.wrap(usde);
        currency1 = Currency.wrap(rseth);

        mintAndApproveCurrency(currency0);
        mintAndApproveCurrency(currency1);

        address hookAddress = address(
            uint160(
                Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG
                    | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
                    | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG
            )
        );

        deployCodeTo("PtHook.sol", abi.encode(manager), hookAddress);

        hook = PtHook(hookAddress);
        hook.setPendleRouter(router);

        IPtHook.SetMarketParams memory params;
        params.market0 = usdePendleMarket;
        params.market1 = rsEthPendleMarket;

        (key,) = initPoolAndAddLiquidity(currency0, currency1, hook, fee, SQRT_PRICE_1_1, abi.encode(params));
    }

    function test_fuzzSwapZeroToOne(uint256 seed) public {
        uint256 swapAmount = bound(seed, 1e18, 1_000_000 * 1e18);
        swapZeroToOne(swapAmount);
    }

    function test_fuzzSwapOneToZero(uint256 seed) public {
        uint256 swapAmount = bound(seed, 0.0005e18, 300 * 1e18);
        swapOneToZero(swapAmount);
    }

    // claim fee after swap same block (should get less fee)
    function test_fuzzClaimFeeAfterSwap(uint256 seed0) public {
        test_fuzzSwapZeroToOne(seed0);
        test_fuzzSwapOneToZero(seed0);
        (uint256 fee0, uint256 fee1) =
            hook.getUserTradingFee(address(modifyLiquidityRouter), key.toId(), LIQUIDITY_PARAMS);
        console.log(">>>>>>>>>>");
        console.log("fee0");
        console.log(fee0);
        console.log("fee1");
        console.log(fee1);
        BalanceDelta delta = modifyLiquidityRouter.modifyLiquidity(key, CLIAM_FEE_PARAMS, ZERO_BYTES);
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());
        // note: without timeskip, the fee should be the less than fee0Bf
        assertLe(int256(delta.amount0()).toUint256(), fee0, "not loss on fee0");
        assertLe(int256(delta.amount1()).toUint256(), fee1, "not loss on fee1");
    }

    // claim fee after swap timeskip (should get move fee)
    function test_fuzzCliamFeeAfterSwap10day(uint256 seed) public {
        test_fuzzSwapZeroToOne(seed);
        test_fuzzSwapOneToZero(seed);
        (uint256 fee0, uint256 fee1) =
            hook.getUserTradingFee(address(modifyLiquidityRouter), key.toId(), LIQUIDITY_PARAMS);
        skip(86400 * 10);
        console.log(">>>>>>>>>>");
        console.log("fee0");
        console.log(fee0);
        console.log("fee1");
        console.log(fee1);
        BalanceDelta delta = modifyLiquidityRouter.modifyLiquidity(key, CLIAM_FEE_PARAMS, ZERO_BYTES);
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());
        // note: without timeskip, the fee should be the less than fee0Bf
        assertGe(int256(delta.amount0()).toUint256(), fee0, "not win on fee0");
        assertGe(int256(delta.amount1()).toUint256(), fee1, "not win on fee1");
    }

    // test remove after swap (same block vs timeskip)
    function test_fuzzRemoveLiquidityAfterSwap(uint256 seed) public {
        test_fuzzSwapZeroToOne(seed);
        test_fuzzSwapOneToZero(seed);
        uint256 snapshotId = vm.snapshot();
        BalanceDelta delta = modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        console.logInt(delta.amount0());
        console.logInt(delta.amount1());
        vm.revertTo(snapshotId);
        skip(86400 * 10);
        BalanceDelta delta10day = modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
        console.logInt(delta10day.amount0());
        console.logInt(delta10day.amount1());
        assertGe(delta10day.amount0(), delta.amount0(), "not win on fee0");
        assertGe(delta10day.amount1(), delta.amount1(), "not win on fee1");
    }

    // test unset market after swap
    function test_fuzzUnsetMarketAfterSwap(uint256 seed) public {
        test_fuzzSwapZeroToOne(seed);
        test_fuzzSwapOneToZero(seed);
        IPtHook.SetMarketParams memory params;
        params.market0 = address(0);
        params.market1 = address(0);
        hook.setMarket(key, params);
        IPtHook.MarketInfo memory marketInfo = hook.getMarketInfo(key.toId());
        assertEq(marketInfo.market0, address(0), "not unset market0");
        assertEq(marketInfo.market1, address(0), "not unset market1");
        assertEq(marketInfo.totalFee0, 0, "not unset totalFee0");
        assertEq(marketInfo.totalPt0, 0, "not unset totalPt0");
        assertEq(marketInfo.totalFee1, 0, "not unset totalFee1");
        assertEq(marketInfo.totalPt1, 0, "not unset totalPt1");
    }

    // test swap after unset market
    function test_fuzzSwapAfterUnsetMarket(uint256 seed) public {
        test_fuzzSwapZeroToOne(seed);
        test_fuzzSwapOneToZero(seed);
        IPtHook.SetMarketParams memory params;
        params.market0 = address(0);
        params.market1 = address(0);
        hook.setMarket(key, params);
        test_fuzzSwapZeroToOne(seed);
        test_fuzzSwapOneToZero(seed);
    }

    // test remove after unset market
    function test_fuzzRemoveAfterUnsetMarket(uint256 seed) public {
        test_fuzzSwapZeroToOne(seed);
        test_fuzzSwapOneToZero(seed);
        IPtHook.SetMarketParams memory params;
        params.market0 = address(0);
        params.market1 = address(0);
        hook.setMarket(key, params);
        test_fuzzRemoveLiquidityAfterSwap(seed);
    }

    // test change market
    function test_changeMarket(uint256 seed) public {
        test_fuzzSwapZeroToOne(seed);
        test_fuzzSwapOneToZero(seed);
        IPtHook.SetMarketParams memory params;
        address newRsEthPendleMarket = 0x6b4740722e46048874d84306B2877600ABCea3Ae;
        params.market0 = address(0);
        params.market1 = newRsEthPendleMarket;
        params.guessPtOut1 = ApproxParams({
            guessMin: 0,
            guessMax: type(uint256).max,
            guessOffchain: 0,
            maxIteration: 256,
            eps: 100000000000000
        });
        IPtHook.MarketInfo memory marketInfoBf = hook.getMarketInfo(key.toId());
        hook.setMarket(key, params);
        IPtHook.MarketInfo memory marketInfo = hook.getMarketInfo(key.toId());
        assertEq(marketInfo.market0, address(0), "not unset market0");
        assertEq(marketInfo.market1, newRsEthPendleMarket, "not set market1");
        assertEq(marketInfo.totalFee0, 0, "not unset totalFee0");
        assertEq(marketInfo.totalPt0, 0, "not unset totalPt0");
        assertEq(marketInfo.totalFee1, marketInfoBf.totalFee1, "wrong totalFee1");
        assertApproxEqRel(marketInfo.totalPt1, marketInfoBf.totalPt1, 0.5e17, "not totalPt0");
    }

    // test swap after change market
    function test_fuzzSwapAfterChangeMarket(uint256 seed) public {
        test_changeMarket(seed);
        skip(1);
        test_fuzzSwapZeroToOne(seed);
        test_fuzzSwapOneToZero(seed);
    }

    // test remove after change market
    function test_fuzzRemoveAfterChangeMarket(uint256 seed) public {
        test_changeMarket(seed);
        skip(1);
        test_fuzzRemoveLiquidityAfterSwap(seed);
    }
}
