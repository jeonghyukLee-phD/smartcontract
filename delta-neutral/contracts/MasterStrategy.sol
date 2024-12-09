// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/INeutral.sol";
import "./interfaces/ILpPool.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IFactory.sol";
import "hardhat/console.sol";

contract MasterStrategy is Ownable {
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
        mapping (uint256=>uint256) debt_value;
        mapping (uint256=>uint256) interest;
    }

    struct Strategy {
        mapping(uint256 => address) addr;
        mapping(uint256 => address) stb_asset;
        mapping(uint256 => address) vrb_asset;
    }

    Asset asset;
    Debt debt;
    Strategy strategy;
    address factory;

constructor(address initialOwner,address _factory) Ownable(initialOwner) {
        factory = _factory;
    }

    function SetStrategyInfo(uint256 idx) external onlyOwner {
        strategy.addr[idx] = IFactory(factory).getStrategy(idx);
        strategy.stb_asset[idx] = INeutral(strategy.addr[idx])
            .assetView()
            .stb_asset;
        strategy.vrb_asset[idx] = INeutral(strategy.addr[idx])
            .assetView()
            .vrb_asset;
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
        uint256 strategy_total_value = INeutral(strategy.addr[idx])
            .assetTotalValue();
        (uint256 swap_pool_value, , , , ) = INeutral(strategy.addr[idx])
            .swapPoolInfo();
        (uint256 lending_pool_value, ) = INeutral(strategy.addr[idx])
            .CollateralInfo();
        (uint256 debt_value, , , ) = INeutral(strategy.addr[idx]).DebtInfo();

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

    function updateStrategyInfo() public onlyOwner {
        asset.total_asset_value = 0;
        asset.profit = 0;
        asset.loss = 0;
        uint256 profit;
        uint256 loss;
        for (uint256 i = 0; i < IFactory(factory).getPositionNum(); i++) {
                    if(debt.total_debt_value>0){
            debt.total_debt_value -= debt.debt_value[i];
            debt.total_interest -= debt.interest[i];
        }
        INeutral(strategy.addr[i]).updateCollateralInfo(0, 0);
        INeutral(strategy.addr[i]).updateDebtInfo(0, 0);
            asset.total_asset_value+= INeutral(strategy.addr[i])
                .assetTotalValue();
            (profit,loss) = INeutral(strategy.addr[i]).computeProfitAndLoss();
            asset.profit += profit;
            asset.loss += loss;
            console.log("get profit: ",profit);
            console.log(asset.profit);
            (debt.debt_value[i], , , debt.interest[i]) = INeutral(
                strategy.addr[i]
            ).DebtInfo();
            debt.total_debt_value += debt.debt_value[i];
            debt.total_interest += debt.interest[i];
        }
    }

    function TotalStrategyValue() external view returns (uint256) {
        return asset.total_asset_value;
    }

    function TotalDebtInfo() external view returns (uint256, uint256) {
        return (debt.total_debt_value, debt.total_interest);
    }

    function getProfit() external view returns (uint256){
        return asset.profit;
    }

    function getLoss() external view returns (uint256){
        return asset.loss;
    }

    function deposit(uint256 idx, uint256 amount) external onlyOwner {
        IERC20(strategy.stb_asset[idx]).transferFrom(msg.sender, address(this), amount);
        IERC20(strategy.stb_asset[idx]).approve(strategy.addr[idx],amount);
        INeutral(strategy.addr[idx]).deposit(amount);
        updateStrategyInfo();
    }

    function withdraw(uint256 idx, uint256 amount) external onlyOwner{
        INeutral(strategy.addr[idx]).withdraw(amount);
        updateStrategyInfo();
    }

    function rebalance(uint256 idx) external onlyOwner{
        INeutral(strategy.addr[idx]).rebalance();
        updateStrategyInfo();
    }
}
