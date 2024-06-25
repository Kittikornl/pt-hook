// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

interface IPendleSyToken {
    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        external
        payable
        returns (uint256 amountSharesOut);

    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external returns (uint256 amountTokenOut);

    function yieldToken() external view returns (address);

    function claimRewards(address user) external returns (uint256[] memory rewardAmounts);

    function approve(address spender, uint256 amount) external returns (bool);

    function exchangeRate() external view returns (uint256);
}
