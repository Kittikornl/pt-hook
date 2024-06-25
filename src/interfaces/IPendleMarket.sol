// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

struct UserReward {
    uint128 index;
    uint128 accrued;
}

// 1 SLOT = 256 bits

interface IPendleMarket {
    function userReward(address token, address user) external view returns (UserReward memory);

    function redeemRewards(address user) external returns (uint256[] memory rewards);

    function getRewardTokens() external view returns (address[] memory);

    function readTokens() external view returns (address sy, address pt, address yt);

    function isExpired() external view returns (bool);

    function observations(uint256 index) external view returns (uint32, uint216, bool);

    function _storage()
        external
        view
        returns (
            int128 totalPt,
            int128 totalSy,
            uint96 lastLnImpliedRate,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext
        );
}
