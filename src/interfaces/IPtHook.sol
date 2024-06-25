// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolId} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {ApproxParams} from "./IPendleRouter.sol";

// note: this hook will use trading fee to buy and hold PT
interface IPtHook {
    event SetMarket(PoolId indexed id, address indexed market0, address indexed market1);
    event RealizeFee(PoolId indexed id, address indexed market, uint256 fee, uint256 realizedFee);
    event BuyPt(PoolId indexed id, address indexed market, uint256 amount, uint256 ptAmount);
    event SellPt(PoolId indexed id, address indexed market, uint256 ptAmount, uint256 amt);
    event SetPendleRouter(address indexed router);

    struct MarketInfo {
        address market0; // market of pt0
        address market1; // market of pt1
        uint128 totalFee0; // total trading fee of token0
        uint128 totalPt0; // total bought pt0 (if market0 is address(0), this will be 0)
        uint128 totalFee1; // total trading fee of token1
        uint128 totalPt1; // total bought pt1 (if market1 is address(0), this will be 0)
    }

    struct SetMarketParams {
        address market0;
        address market1;
        ApproxParams guessPtOut0;
        ApproxParams guessPtOut1;
    }

    /// @dev get current market info of provided pool id
    /// @param poolId pool id
    /// @return market info
    function getMarketInfo(PoolId poolId) external view returns (MarketInfo memory);

    /// @dev hook owner set market of provided pool key
    /// @param key pool key
    /// @param params market params
    function setMarket(PoolKey calldata key, SetMarketParams calldata params) external;

    /// @dev get user trading fee of provided pool id
    /// @param router router address
    function setPendleRouter(address router) external;
}
