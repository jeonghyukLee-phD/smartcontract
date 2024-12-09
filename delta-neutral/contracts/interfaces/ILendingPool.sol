// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILendingPool{
    /* view */
    function balanceOf(address owner) external view returns (uint);

    /* execute */
    function balanceOfUnderlying(address owner) external returns (uint);
    function mint(uint mintAmount) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function enterMarkets(address[] memory cTokens) external returns (uint256[] memory);
    
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);

    function borrow(uint borrowAmount) external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);

    function repayBorrow(uint repayAmount) external returns (uint);
}

interface ILendingController {
    function enterMarkets(address[] memory cTokens) external returns (uint256[] memory);
}