// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/INeutralV2.sol";
import "./interfaces/ILpPool.sol";
import "./interfaces/ILendingPoolV2.sol";
import "./interfaces/IFactory.sol";
import "hardhat/console.sol";

contract MasterStrategyV2 is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    uint256 total_value;
    address usdc;

    struct Asset {
        uint256 total_asset_value;
        uint256 profit;
        uint256 loss;
    }

    struct Debt {
        uint256 total_debt_value;
        uint256 total_interest;
        mapping(uint256 => uint256) debt_value;
        mapping(uint256 => uint256) interest;
    }

    struct Strategy {
        mapping(uint256 => address) addr;
        mapping(uint256 => address) stb_asset;
        mapping(uint256 => address) vrb_asset;
        mapping(uint256 => uint256) pnl_positive;
        mapping(uint256 => uint256) pnl_negative;
        mapping(uint256 => uint256) cum_pnl_positive;
        mapping(uint256 => uint256) cum_pnl_negative;
        mapping(uint256 => uint256) fund_price;
    }

    Asset asset;
    Debt debt;
    Strategy strategy;
    address factory;

    constructor(address initialOwner, address _factory) Ownable(initialOwner) {
        factory = _factory;
    }

    function SetStrategyInfo(uint256 idx) external onlyOwner {
        strategy.addr[idx] = IFactory(factory).getStrategy(idx);
        console.log(strategy.addr[idx]);
        strategy.stb_asset[idx] = INeutralV2(strategy.addr[idx])
            .assetView()
            .stb_asset;
        strategy.vrb_asset[idx] = INeutralV2(strategy.addr[idx])
            .assetView()
            .vrb_asset;
        strategy.fund_price[idx] = 10**18;
    }

    function getStrategyInfo(uint256 idx)
        public
        view
        returns (
            address,
            address,
            address,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 strategy_total_value = INeutralV2(strategy.addr[idx])
            .assetTotalValue();
        (uint256 swap_pool_value, , , , ) = INeutralV2(strategy.addr[idx])
            .swapPoolInfo();
        (uint256 lending_pool_value, ) = INeutralV2(strategy.addr[idx])
            .CollateralInfo();
        (uint256 debt_value, , , ) = INeutralV2(strategy.addr[idx]).DebtInfo();

        return (
            strategy.addr[idx],
            strategy.stb_asset[idx],
            strategy.vrb_asset[idx],
            strategy_total_value,
            swap_pool_value,
            lending_pool_value,
            debt_value
        );
    }

    function _updatePnL(uint256 idx) internal {
        (strategy.pnl_positive[idx], strategy.pnl_negative[idx]) = INeutralV2(
            strategy.addr[idx]
        ).computePnLRatio();
    }

    function _updateFundPrice(uint256 idx) internal {
        console.log("before updated fund price: ", strategy.fund_price[idx]);
        strategy.fund_price[idx] = getFundPrice(idx);
        console.log("after updated fund price: ", strategy.fund_price[idx]);
    }

    function _updateStrategyTvl(uint256 idx) internal {
        INeutralV2(strategy.addr[idx]).updateTvl();
    }

    function updateStrategyTvlAll() public {
        for (uint256 i = 0; i < IFactory(factory).getPositionNum(); i++) {
            _updateStrategyTvl(i);
        }
    }

    function updateStrategyInfo() public onlyOwner {
        asset.total_asset_value = 0;
        asset.profit = 0;
        asset.loss = 0;
        uint256 profit;
        uint256 loss;
        for (uint256 i = 0; i < IFactory(factory).getPositionNum(); i++) {
            if (debt.total_debt_value > 0) {
                debt.total_debt_value -= debt.debt_value[i];
                debt.total_interest -= debt.interest[i];
            }
            INeutralV2(strategy.addr[i]).updateCollateralInfo(0, 0);
            INeutralV2(strategy.addr[i]).updateDebtInfo(0, 0);
            asset.total_asset_value += INeutralV2(strategy.addr[i])
                .assetTotalValue();
            (profit, loss) = INeutralV2(strategy.addr[i])
                .computeProfitAndLoss();
            asset.profit += profit;
            asset.loss += loss;
            console.log("get profit: ", profit);
            console.log(asset.profit);
            (debt.debt_value[i], , , debt.interest[i]) = INeutralV2(
                strategy.addr[i]
            ).DebtInfo();
            debt.total_debt_value += debt.debt_value[i];
            debt.total_interest += debt.interest[i];
            _updateCumPnL(i);
            _updatePnL(i);
            _updateFundPrice(i);
        }
    }

    function _updateCumPnL(uint256 idx) internal returns (uint256, uint256) {
        (uint256 current_profit, uint256 current_loss) = INeutralV2(
            strategy.addr[idx]
        ).computePnLRatio();
        if (current_profit >= 0 && current_loss == 0) {
            console.log("profit occurs");
            /*
            case 1: cum_profit > 0 && current_profit > 0
            case 2: cum_negative >0 && current_profit >0 , thus cum_positive > 0
            case 3: cum_negative >0 && current_profit> 0 but cum_negative >0  yet.
            case 4: cum_negative is over 100% 
            */
            if (
                strategy.cum_pnl_positive[idx] >= 0 &&
                strategy.cum_pnl_negative[idx] == 0
            ) {
                console.log("case 1-1");
                strategy.cum_pnl_positive[idx] =
                    ((10**18 + strategy.cum_pnl_positive[idx]) *
                        (10**18 + current_profit)) /
                    10**18 -
                    10**18;
                strategy.cum_pnl_negative[idx] = 0;
            } else if (
                0 < strategy.cum_pnl_negative[idx] &&
                strategy.cum_pnl_negative[idx] < 10**18
            ) {
                if (
                    current_profit >=
                    (strategy.cum_pnl_negative[idx] * 10**18) /
                        (10**18 - strategy.cum_pnl_negative[idx])
                ) {
                    console.log("case 1-2");
                    // strategy.cum_pnl_positive[idx] =
                    //     ((10**18 - strategy.cum_pnl_negative[idx]) *
                    //         (10**18 + current_profit)) /
                    //     10**18 -
                    //     10**18;
                    strategy.cum_pnl_positive[idx]= current_profit - ((strategy.cum_pnl_negative[idx]*current_profit)/10**18)-strategy.cum_pnl_negative[idx];
                    strategy.cum_pnl_negative[idx] = 0;
                } else {
                    console.log("case 1-3");
                    strategy.cum_pnl_positive[idx] = 0;
                    console.log("pnl_N: ", strategy.cum_pnl_negative[idx]);
                    console.log("current_pnl_profit: ", current_profit);
                    strategy.cum_pnl_negative[idx]=(strategy.cum_pnl_negative[idx]*current_profit)/10**18 +strategy.cum_pnl_negative[idx]-current_profit;
                }
            } else {

                console.log("cum loss is over 100%");
                strategy.cum_pnl_positive[idx] = 0;
                console.log("pnl_N: ", strategy.cum_pnl_negative[idx]);
                console.log("current_pnl_profit: ", current_profit);
                strategy.cum_pnl_negative[idx]=(strategy.cum_pnl_negative[idx]*current_profit)/10**18 +strategy.cum_pnl_negative[idx]-current_profit;
            }
        } else {
            console.log("loss occurs");
            /*
            case 1: cum_negative > 0 && current_loss > 0
            case 2: cum_positive > 0 && current_loss > 0 but cum_positive > 0 
            case 3: cum_positive > 0 && currnet_loss > 0 thus, cum_negative > 0
             */
            if (strategy.cum_pnl_negative[idx] > 0) {
                console.log("case 2-1");
                strategy.cum_pnl_positive[idx] = 0;
                strategy.cum_pnl_negative[idx] =
                    ((10**18 + strategy.cum_pnl_negative[idx]) *
                        (10**18 + current_loss)) /
                    10**18 -
                    10**18;
            } else if (
                strategy.cum_pnl_positive[idx] >= 0 &&
                current_loss <
                (strategy.cum_pnl_positive[idx] * 10**18) /
                    (10**18 + strategy.cum_pnl_positive[idx])
            ) {
                console.log("case 2-2");
                strategy.cum_pnl_positive[idx] =
                    ((10**18 + strategy.cum_pnl_positive[idx]) *
                        (10**18 - current_loss)) /
                    10**18 -
                    10**18;
                strategy.cum_pnl_negative[idx] = 0;
            } else if (
                strategy.cum_pnl_positive[idx] >= 0 &&
                current_loss >
                (strategy.cum_pnl_positive[idx] * 10**18) /
                    (10**18 + strategy.cum_pnl_positive[idx])
            ) console.log("case 2-3");
            strategy.cum_pnl_positive[idx] = 0;
            // strategy.cum_pnl_negative[idx] =
            //     ((10**18 - strategy.cum_pnl_positive[idx]) *
            //         (10**18 + current_loss)) /
            //     10**18 -
            //     10**18;
            strategy.cum_pnl_negative[idx] = (strategy.cum_pnl_positive[idx]*current_loss)/10**18 + current_loss - strategy.cum_pnl_positive[idx];
        }

        return (strategy.cum_pnl_positive[idx], strategy.cum_pnl_negative[idx]);
    }

    function TotalStrategyValue() external view returns (uint256) {
        return asset.total_asset_value;
    }

    function TotalDebtInfo() external view returns (uint256, uint256) {
        return (debt.total_debt_value, debt.total_interest);
    }

    function getProfit() external view returns (uint256) {
        return asset.profit;
    }

    function getLoss() external view returns (uint256) {
        return asset.loss;
    }

    function getFundPrice(uint256 idx)
        public
        view
        returns (uint256 fund_price)
    {
        (uint256 current_profit, uint256 current_loss) = INeutralV2(
            strategy.addr[idx]
        ).computePnLRatio();
        console.log("current fund price: ", strategy.fund_price[idx]);
        console.log("current_profit: ", current_profit);
        if (current_profit > 0) {
            fund_price =
                (strategy.fund_price[idx] * ((10**18) + current_profit)) /
                (10**18);
        } else {
            fund_price =
                (strategy.fund_price[idx] * ((10**18) - current_loss)) /
                (10**18);
        }
    }

    function getFundAmount(uint256 idx)
        public
        view
        returns (uint256 fund_amount)
    {
        (, , , uint256 value, , , ) = getStrategyInfo(idx);
        uint256 fund_price = getFundPrice(idx);

        fund_amount = (value * 10**18) / fund_price;
    }

    function getCumPnL(uint256 idx) public view returns (uint256, uint256) {
        return (strategy.cum_pnl_positive[idx], strategy.cum_pnl_negative[idx]);
    }

    function deposit(uint256 idx, uint256 amount) external onlyOwner {
        IERC20(strategy.stb_asset[idx]).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        IERC20(strategy.stb_asset[idx]).approve(strategy.addr[idx], amount);
        INeutralV2(strategy.addr[idx]).deposit(amount);
        updateStrategyInfo();
    }

    function withdraw(uint256 idx, uint256 amount) external onlyOwner {
        INeutralV2(strategy.addr[idx]).withdraw(amount);
        updateStrategyInfo();
    }

    function withdrawAll(uint256 idx) external onlyOwner {
        INeutralV2(strategy.addr[idx]).withdrawAll();
        updateStrategyInfo();
    }

    function rebalance(uint256 idx) external onlyOwner {
        INeutralV2(strategy.addr[idx]).rebalance();
        updateStrategyInfo();
    }

    function claim(uint256 idx) external onlyOwner {
        INeutralV2(strategy.addr[idx]).claim();
        updateStrategyInfo();
    }
}
