// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

interface INeutral {
        struct Asset {
        address stb_asset;
        address vrb_asset;
        uint256 stb_decimal;
        uint256 vrb_decimal;
        address reward;
        uint256 vrb_weight;
        uint256 stb_weight;
        uint256 collateral_rate;
        uint256 principal_value;
    }

    struct Capital {
        uint256 vrb_price;
        uint256 stb_price;
        uint256 stb_principal;
        uint256 vrb_principal;
    }

    struct Swap_pool {
        address router;
        address lp;
        address farm;
        uint256 pid;
        uint256 stb_principal;
        uint256 vrb_principal;
    }

    struct Reward {
        address pair;
    }

    struct Collateral {
        address addr;
        address controller;
        uint256 amt;
        uint256 principal;
    }

    struct Debt {
        address addr;
        uint256 amt;
        uint256 principal;
    }

    function initialize_1(
        address stb_asset,
        address vrb_asset,
        address reward_asset,
        uint256 vrb_weight,
        uint256 collateral_rate
    ) external;

    function initialize_2(
        address router,
        address farm,
        address lp,
        uint256 pid,
        address collateralAddr,
        address controller,
        address loanAddr,
        address owner
    ) external;

    function setStrategist(address strategist) external;

    function assetView() external view returns (Asset memory);
    function setCapitalPrice(address pair) external;

    function setRewardPrice(address pair) external;

    function callVrbPrice(address lp) external view returns (uint256);

    // function requiredLiquidity(
    //     uint256 vrbAmt
    // ) external view returns (uint256 lpAmount);

    // function computeRebalanceAmt() external view returns (int256 adjustVrbAmt);

    function swapPoolInfo()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256);

    function CollateralInfo() external view returns (uint256, uint256);

    function CapitalInfo() external view returns (uint256, uint256, uint256);

    function DebtInfo()
        external
        view
        returns (uint256, uint256, uint256, uint256);

    function assetTotalValue() external view returns (uint256 totalValue);

    function depositCollateral(uint256 collateralAmt) external;

    function withdrawCollateral(uint256 cTokenAmt, uint256 debtAmt) external;

    function borrow(uint256 borrowAmt) external;

    function repay(uint256 repayAmt) external;

    function stake(uint256 stbAmt, uint256 vrbAmt) external;

    function unstake(uint256 lpAmt) external;

    function updateCollateralInfo(
        uint256 depositAmt,
        uint256 withdrawAmt
    ) external;

    function computeProfitAndLoss() external returns (uint256,uint256);

    function updateDebtInfo(uint256 borrowAmt, uint256 repayAmt) external;

    //============== User Actions ==============//

    function deposit(uint256 Amt) external;

    function withdraw(uint256 lpAmt) external;

    function withdrawAll() external;

    function rebalance() external;

    function compound() external;
}
