// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/INeutralV2.sol";
import "./interfaces/ILpPool.sol";
import "./interfaces/ILendingPoolV2.sol";
import "./interfaces/IPriceOracle.sol";

import "hardhat/console.sol";

contract NeutralV2 is INeutralV2, Ownable {
    using SafeERC20 for IERC20;
    using Address for address;

    uint256 public constant MAXWEIGHT = 10000;
    uint256 public constant DEVIDER = 1000000;
    Asset public asset;
    Swap_pool public swap_pool;
    Collateral public collateral;
    Capital public capital;
    Debt public debt;
    Reward public reward;

    address internal _factory;
    address _strategist;

    address public priceOracle = 0x2553f4eeb82d5A26427b8d1106C51499CBa5D99c;

    modifier onlyFactory() {
        require(
            msg.sender == _factory,
            "Neutral::onlyFactory: not a valid sender."
        );
        _;
    }

    modifier onlyStrategist() {
        require(msg.sender == _strategist, "No permission");
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {
        _factory = msg.sender;
    }

    function initialize_1(
        address stb_asset,
        address vrb_asset,
        address reward_asset,
        uint256 vrb_weight,
        uint256 collateral_rate
    ) external onlyFactory {
        asset.stb_asset = stb_asset;
        asset.vrb_asset = vrb_asset;
        asset.stb_decimal = IERC20Metadata(stb_asset).decimals();
        asset.vrb_decimal = IERC20Metadata(vrb_asset).decimals();
        asset.reward = reward_asset;
        asset.vrb_weight = vrb_weight;
        asset.stb_weight = MAXWEIGHT - vrb_weight;
        require(collateral_rate > 1200000, "insufficient collateral rate");
        asset.collateral_rate = collateral_rate;
    }

    function initialize_2(
        address router,
        address farm,
        address lp,
        uint256 pid,
        address aToken,
        address pool,
        address owner
    ) external onlyFactory {
        swap_pool.router = router;
        swap_pool.farm = farm;
        swap_pool.lp = lp;
        swap_pool.pid = pid;

        collateral.aToken = aToken;
        collateral.pool = pool;

        transferOwnership(owner);
    }

    // initialize_3
    function setCapitalPrice(address pair) external onlyFactory {
        (, , , , uint80 usdcPrice) = IPriceOracle(priceOracle)
            .latestRoundData();
        capital.stb_price = usdcPrice;
        capital.vrb_price = callVrbPrice(pair);
    }

    // initialize_4
    function setRewardPrice(address pair) external onlyFactory {
        reward.pair = pair;
    }

    /**
     * @notice Load latest price of variable asset
     * @param lp The address of pool
     */
    function callVrbPrice(address lp) public view returns (uint256) {
        uint256 reserve0;
        uint256 reserve1;
        uint256 current_price;
        if (ILpPool(lp).token0() == asset.stb_asset) {
            (reserve0, reserve1, ) = ILpPool(lp).getReserves();
            reserve0 = reserve0 * (10**(asset.vrb_decimal - asset.stb_decimal));
            current_price = (reserve0 * (10**18)) / reserve1;
        } else {
            (reserve1, reserve0, ) = ILpPool(lp).getReserves();
            current_price =
                (reserve0 *
                    (10**18) *
                    (10**(asset.vrb_decimal - asset.stb_decimal))) /
                reserve1;
        }
        return current_price;
    }

    function callStbPrice() public view returns (uint256) {
        int256 answer;
        (, answer, , , ) = IPriceOracle(priceOracle).latestRoundData();
        uint256 usdcPrice = uint256(answer) * (10**10);
        return usdcPrice;
    }

    function assetView() public view returns (Asset memory) {
        return asset;
    }

    /**
     * @notice Load latest amounts of tokens, values, profit or loss in Swap pool
     */
    function swapPoolInfo()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 liquidity, ) = IFarm(swap_pool.farm).userInfo(
            swap_pool.pid,
            address(this)
        );
        (uint256 reserve0, uint256 reserve1, ) = ILpPool(swap_pool.lp)
            .getReserves();

        uint256 totalSupply = IERC20(swap_pool.lp).totalSupply();
        uint256 stb_amt;
        uint256 vrb_amt;
        if (ILpPool(swap_pool.lp).token0() == asset.stb_asset) {
            stb_amt = (liquidity * reserve0) / totalSupply;
            vrb_amt = (liquidity * reserve1) / totalSupply;
        } else {
            stb_amt = (liquidity * reserve1) / totalSupply;
            vrb_amt = (liquidity * reserve0) / totalSupply;
        }
        uint256 stb_value = (stb_amt * callStbPrice()) /
            (10**asset.stb_decimal);
        uint256 vrb_value = (vrb_amt * callVrbPrice(swap_pool.lp)) /
            (10**asset.vrb_decimal);
        return (stb_value + vrb_value, stb_amt, vrb_amt, stb_value, vrb_value);
    }

    /**
     * @notice Load latest amounts of collateral, collateral value, profit or loss in lending pool
     */
    function CollateralInfo() public view returns (uint256, uint256) {
        uint256 CollateralAmt = collateral.amt;
        uint256 CollateralValue = (CollateralAmt * callStbPrice()) /
            (10**asset.stb_decimal);
        return (CollateralValue, CollateralAmt);
    }

    /**
     * @notice Load latest token amounts of swapPool + Lending pool, value of stable tokens, value of variable tokens, stable interest, variable interest, is surplus or deficit
     */

    function CapitalInfo()
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        (
            uint256 swap_total_value,
            uint256 swap_stb_amt,
            uint256 swap_vrb_amt,
            ,

        ) = swapPoolInfo();
        (uint256 collateralValue, uint256 collateralAmt) = CollateralInfo();
        return (
            swap_total_value + collateralValue,
            swap_stb_amt + collateralAmt,
            swap_vrb_amt
        );
    }

    /**
     * @notice Load latest value of debt, amount of debt, principal of debt, interest
     */
    function DebtInfo()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 debtValue = (debt.amt * callVrbPrice(swap_pool.lp)) /
            10**(asset.vrb_decimal);
        uint256 realTimeDebt = debt.amt;
        uint256 interest;
        if (debt.principal > debt.amt) {
            interest = 0;
        } else {
            interest = debt.amt - debt.principal;
        }

        return (debtValue, realTimeDebt, debt.principal, interest);
    }

    function assetTotalValue() public view returns (uint256 totalValue) {
        (uint256 capitalVal, , ) = CapitalInfo();
        (uint256 debtVal, , , ) = DebtInfo();
        uint256 left_stb = IERC20(asset.stb_asset).balanceOf(address(this));
        uint256 left_vrb = IERC20(asset.vrb_asset).balanceOf(address(this));
        uint256 left_value = ((left_stb * callStbPrice()) /
            10**asset.stb_decimal) +
            ((left_vrb * callVrbPrice(swap_pool.lp)) / 10**asset.vrb_decimal);
        if (capitalVal > debtVal) {
            totalValue = left_value + capitalVal - debtVal;
        } else {
            totalValue = 0;
        }
        return totalValue;
    }

    function computeProfitAndLoss() external view returns (uint256, uint256) {
        uint256 current_value = assetTotalValue();
        uint256 profit = 0;
        uint256 loss = 0;
        if (asset.principal_value < current_value) {
            profit = current_value - asset.principal_value;
        } else {
            loss = asset.principal_value - current_value;
        }
        return (profit, loss);
    }

    function computePnLRatio()
        public
        view
        returns (uint256 pnl_positive, uint256 pnl_negative)
    {
        uint256 current_value = assetTotalValue();
        console.log("prior value: ", asset.principal_value);
        console.log("current value: ", current_value);
        if (
            (current_value > asset.principal_value) &&
            (asset.principal_value > 0)
        ) {
            pnl_positive =
                ((10**18) * current_value) /
                asset.principal_value -
                (10**18);
            pnl_negative = 0;
        } else if (
            (asset.principal_value) > 0 &&
            (current_value < asset.principal_value)
        ) {
            pnl_positive = 0;
            pnl_negative =
                (10**18) -
                ((current_value * (10**18)) / asset.principal_value);
        } else {
            pnl_positive = 0;
            pnl_negative = 0;
        }

        return (pnl_positive, pnl_negative);
    }

    /**
     * @notice Supply collateral to lending pool
     * @param collateralAmt The amounts of the collateral asset
     */
    function depositCollateral(uint256 collateralAmt) external {
        IERC20(asset.stb_asset).safeTransferFrom(
            address(msg.sender),
            address(this),
            collateralAmt
        );
        _depositCollateral(collateralAmt);
        // _updateAssetInfo();
    }

    function _depositCollateral(uint256 collateralAmt) internal {
        address[] memory collaterals = new address[](1);
        collaterals[0] = asset.stb_asset;
        IERC20(asset.stb_asset).approve(collateral.pool, collateralAmt);
        ILendingPoolV2(collateral.pool).deposit(
            asset.stb_asset,
            collateralAmt,
            address(this),
            0
        );
        // ILendingPool(collateral.addr).safeTransfer(msg.sender,ILendingPool(collateral.addr).balanceOf(address(this)));
        updateCollateralInfo(collateralAmt, 0);
        _updateCapitalInfo();
    }

    /**
     * @notice Withdraw collateral to lending pool
     * @param cTokenAmt The amounts of the lp token for the depositted collateral
     * @param debtAmt The amounts of debt that will be redeemed to the lending pool
     */
    function withdrawCollateral(uint256 cTokenAmt, uint256 debtAmt)
        external
        onlyOwner
    {
        _withdrawCollateral(cTokenAmt, debtAmt);
        // _updateAssetInfo();
    }

    function _withdrawCollateral(uint256 cTokenAmt, uint256 debtAmt) internal {
        if (debtAmt > 0) {
            _repay(type(uint256).max);
        }
        IERC20(collateral.aToken).approve(collateral.pool, cTokenAmt);
        ILendingPoolV2(collateral.pool).withdraw(
            asset.stb_asset,
            type(uint256).max,
            address(this)
        );
        updateCollateralInfo(
            0,
            IERC20(asset.stb_asset).balanceOf(address(this))
        );
        _updateCapitalInfo();
    }

    /**
     * @notice Borrow variable asset from the lending pool
     * @param borrowAmt The amounts of the variable asset
     */

    function borrow(uint256 borrowAmt) external {
        _borrow(borrowAmt);
        // _updateAssetInfo();
    }

    function _borrow(uint256 borrowAmt) internal {
        ILendingPoolV2(collateral.pool).borrow(
            asset.vrb_asset,
            borrowAmt,
            2,
            0,
            address(this)
        );
        updateDebtInfo(borrowAmt, 0);
    }

    /**
     * @notice Repay variable asset to the lending pool
     * @param repayAmt The amounts of the variable asset
     */
    function repay(uint256 repayAmt) external {
        IERC20(asset.vrb_asset).safeTransferFrom(
            msg.sender,
            address(this),
            repayAmt
        );
        _repay(repayAmt);
        // _updateAssetInfo();
    }

    function _repay(uint256 repayAmt) internal {
        IERC20(asset.vrb_asset).approve(collateral.pool, repayAmt);
        ILendingPoolV2(collateral.pool).repay(
            asset.vrb_asset,
            repayAmt,
            2,
            address(this)
        );
        if (repayAmt == type(uint256).max) {
            debt.amt = 0;
            updateDebtInfo(0, debt.principal);
        } else {
            updateDebtInfo(0, repayAmt);
        }
    }

    /**
     * @notice Supply liquidity to swap pool & stake the lpToken
     * @param stbAmt The amounts of the stable asset
     * @param vrbAmt The amounts of the variable asset
     */
    function stake(uint256 stbAmt, uint256 vrbAmt) external {
        IERC20(asset.stb_asset).safeTransferFrom(
            address(msg.sender),
            address(this),
            stbAmt
        );
        IERC20(asset.vrb_asset).safeTransferFrom(
            address(msg.sender),
            address(this),
            vrbAmt
        );
        _stake(stbAmt, vrbAmt);
        // _updateAssetInfo();
    }

    function _stake(uint256 stbAmt, uint256 vrbAmt) internal {
        IERC20(asset.stb_asset).approve(swap_pool.router, stbAmt);
        IERC20(asset.vrb_asset).approve(swap_pool.router, vrbAmt);
        IRouter(swap_pool.router).addLiquidity(
            asset.stb_asset,
            asset.vrb_asset,
            stbAmt,
            vrbAmt,
            0,
            0,
            address(this),
            type(uint256).max
        );
        uint256 lpAmt = IERC20(swap_pool.lp).balanceOf(address(this));
        IERC20(swap_pool.lp).approve(swap_pool.farm, lpAmt);
        IFarm(swap_pool.farm).deposit(swap_pool.pid, lpAmt);
        _updateSwapPoolInfo(stbAmt, 0, vrbAmt, 0);
        _updateCapitalInfo();
    }

    /**
     * @notice Unstake the lpToken and remove liquidity from the swap pool
     * @param lpAmt The amounts of the lpToken that will be withdrawn
     */
    function unstake(uint256 lpAmt) external onlyOwner {
        uint256 stbAmt;
        uint256 vrbAmt;
        (stbAmt, vrbAmt) = _unstake(lpAmt);
        IERC20(asset.stb_asset).safeTransfer(msg.sender, stbAmt);
        IERC20(asset.vrb_asset).safeTransfer(msg.sender, vrbAmt);
        // _updateAssetInfo();
    }

    function _unstake(uint256 lpAmt) internal returns (uint256, uint256) {
        IFarm(swap_pool.farm).withdraw(swap_pool.pid, lpAmt);
        uint256 withdrawnLpAmt = IERC20(swap_pool.lp).balanceOf(address(this));
        IERC20(swap_pool.lp).approve(swap_pool.router, lpAmt);
        IRouter(swap_pool.router).removeLiquidity(
            asset.stb_asset,
            asset.vrb_asset,
            withdrawnLpAmt,
            0,
            0,
            address(this),
            type(uint256).max
        );
        uint256 stbAmt = IERC20(asset.stb_asset).balanceOf(address(this));
        uint256 vrbAmt = IERC20(asset.vrb_asset).balanceOf(address(this));

        _updateSwapPoolInfo(0, stbAmt, 0, vrbAmt);
        _updateCapitalInfo();
        return (stbAmt, vrbAmt);
    }

    function updateCollateralInfo(uint256 depositAmt, uint256 withdrawAmt)
        public
    {
        uint256 collateral_eth_amt;
        (collateral_eth_amt, , , , , ) = ILendingPoolV2(collateral.pool)
            .getUserAccountData(address(this));

        collateral.amt = (collateral_eth_amt) / (10**(18 - asset.stb_decimal));
        if (collateral.principal < withdrawAmt) {
            collateral.principal = 0;
        } else {
            collateral.principal =
                collateral.principal +
                depositAmt -
                withdrawAmt;
        }
    }

    function _updateCapitalInfo() internal {
        capital.stb_principal = swap_pool.stb_principal + collateral.principal;
        capital.vrb_principal = swap_pool.vrb_principal;
    }

    function _updateSwapPoolInfo(
        uint256 depositStbAmt,
        uint256 withdrawStbAmt,
        uint256 depositVrbAmt,
        uint256 withdrawVrbAmt
    ) internal {
        if (swap_pool.stb_principal > withdrawStbAmt) {
            swap_pool.stb_principal =
                swap_pool.stb_principal +
                depositStbAmt -
                withdrawStbAmt;
        } else {
            swap_pool.stb_principal = 0;
        }
        if (swap_pool.vrb_principal > withdrawVrbAmt) {
            swap_pool.vrb_principal =
                swap_pool.vrb_principal +
                depositVrbAmt -
                withdrawVrbAmt;
        } else {
            swap_pool.vrb_principal = 0;
        }
    }

    function updateDebtInfo(uint256 borrowAmt, uint256 repayAmt)
        public
        returns (uint256)
    {
        // (, , , , uint80 eth_price) = IPriceOracle(priceOracle)
        //     .latestRoundData();

        uint256 debtVal;
        if (debt.principal < repayAmt) {
            debt.principal = 0;
        } else {
            debt.principal = debt.principal + borrowAmt - repayAmt;
        }
        (, debtVal, , , , ) = ILendingPoolV2(collateral.pool)
            .getUserAccountData(address(this));
        debt.amt =
            (debtVal * 10**(asset.vrb_decimal)) /
            callVrbPrice(swap_pool.lp);
        return debtVal;
    }

    function updateTvl() public {
        asset.principal_value = assetTotalValue();
    }

    /**
     * @notice Borrow variable asset from lending pool and deposit the variable asset to swap pool with a stable asset
     * @param Amt The amount of stable asset from the supplier
     */
    function deposit(uint256 Amt) external {
        updateTvl();
        IERC20(asset.stb_asset).safeTransferFrom(
            msg.sender,
            address(this),
            Amt
        );
        _deposit();
    }

    function _deposit() internal {
        address[] memory path = new address[](2);
        path[0] = asset.stb_asset;
        path[1] = asset.vrb_asset;
        uint256[] memory swapAmt = new uint256[](path.length);
        uint256 left_vrbAmt = IERC20(asset.vrb_asset).balanceOf(address(this));
        if (left_vrbAmt > (10**(asset.vrb_decimal - 4))) {
            address[] memory path_vrb_stb = new address[](2);
            path_vrb_stb[0] = path[1];
            path_vrb_stb[1] = path[0];
            IERC20(asset.vrb_asset).approve(
                swap_pool.router,
                type(uint256).max
            );
            IRouter(swap_pool.router).swapExactTokensForTokens(
                left_vrbAmt,
                0,
                path_vrb_stb,
                address(this),
                type(uint256).max
            );
        }
        uint256 initialAsset = IERC20(asset.stb_asset).balanceOf(address(this));
        uint256 collateralAmt = (asset.collateral_rate *
            initialAsset *
            asset.vrb_weight) /
            MAXWEIGHT /
            DEVIDER;
        _depositCollateral(collateralAmt);
        swapAmt = IRouter(swap_pool.router).getAmountsOut(
            (collateralAmt * DEVIDER) / asset.collateral_rate,
            path
        );
        _borrow(swapAmt[path.length - 1]);
        uint256 stbAmt = IERC20(asset.stb_asset).balanceOf(address(this));
        uint256 vrbAmt = IERC20(asset.vrb_asset).balanceOf(address(this));
        _stake(stbAmt, vrbAmt);
    }

    function withdraw(uint256 tokenAmt) external onlyStrategist {
        updateTvl();
        _withdrawAll();
        IERC20(asset.stb_asset).safeTransfer(msg.sender, tokenAmt);
        _deposit();
    }

    /**
     * @notice Unstake all liquidity from staking pool and repay its underlying token to the lendingPool.
     */
    function withdrawAll() external onlyStrategist {
        updateTvl();
        _withdrawAll();
        IERC20(asset.stb_asset).safeTransfer(
            msg.sender,
            IERC20(asset.stb_asset).balanceOf(address(this))
        );
    }

    function _withdrawAll() internal {
        address[] memory path = new address[](2);
        path[0] = asset.stb_asset;
        path[1] = asset.vrb_asset;
        (uint256 totalLpAmt, ) = IFarm(swap_pool.farm).userInfo(
            swap_pool.pid,
            address(this)
        );
        (uint256 stb_bal, uint256 vrb_bal) = _unstake(totalLpAmt);
        (, uint256 CollateralAmt) = CollateralInfo();
        updateDebtInfo(0, 0);
        IERC20(asset.stb_asset).approve(swap_pool.router, type(uint256).max);
        IRouter(swap_pool.router).swapExactTokensForTokens(
            stb_bal,
            0,
            path,
            address(this),
            type(uint256).max
        );
        _withdrawCollateral(CollateralAmt, debt.amt);
        uint256 left_vrbAmt = IERC20(asset.vrb_asset).balanceOf(address(this));
        if (left_vrbAmt > 10**(asset.vrb_decimal - 4)) {
            address[] memory path_vrb_stb = new address[](2);
            path_vrb_stb[0] = path[1];
            path_vrb_stb[1] = path[0];
            IERC20(asset.vrb_asset).approve(
                swap_pool.router,
                type(uint256).max
            );
            IRouter(swap_pool.router).swapExactTokensForTokens(
                left_vrbAmt,
                0,
                path_vrb_stb,
                address(this),
                type(uint256).max
            );
        }
    }

    function setStrategist(address strategist) external onlyFactory {
        _strategist = strategist;
    }

    /**
     * @notice Rebalance a position.
     */

    function rebalance() external onlyOwner {
        updateTvl();
        _withdrawAll();
        _deposit();
    }

    /**
     * @notice Swap reward token to underlying asset and add collateral.
     */
    function claim() external onlyStrategist {
        address[] memory path = new address[](2);
        path[0] = asset.reward;
        path[1] = asset.stb_asset;

        uint256 left_reward = IERC20(asset.reward).balanceOf(address(this));
        console.log("reward: ", left_reward);
        if (left_reward > 10**(asset.vrb_decimal - 4)) {
            IERC20(asset.reward).approve(swap_pool.router, type(uint256).max);
            IRouter(swap_pool.router).swapExactTokensForTokens(
                left_reward,
                0,
                path,
                address(this),
                type(uint256).max
            );
            _depositCollateral(
                IERC20(asset.stb_asset).balanceOf(address(this))
            );
        }
    }
}
