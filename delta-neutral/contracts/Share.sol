// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IShare.sol";
import "./interfaces/INeutral.sol";

contract Share is IShare, ERC20, Ownable {
    using SafeERC20 for IERC20;

    INeutral public _neutral;
    IERC20 public _usdc;

    // TODO treasury

    constructor(address neutral_, address usdc_, address initialOwner) Ownable(initialOwner)
        ERC20("_neutral Share Token", "NST")
    {
        _neutral = INeutral(neutral_);
        _usdc = IERC20(usdc_);
        emit changeNeutral(address(0), neutral_);
        emit changeUSDC(address(0), usdc_);
    }

    function setNeutral(address newNeutral) public onlyOwner {
        address oldNeutral = address(_neutral);
        _neutral = INeutral(newNeutral);
        emit changeNeutral(oldNeutral, newNeutral);
    }

    function setUsdc(address newUsdc) public onlyOwner {
        address oldUsdc = address(_usdc);
        _usdc = IERC20(newUsdc);
        emit changeUSDC(oldUsdc, newUsdc);
    }

    //============== User Actions ==============//

    function mint(address account_, uint256 amount_) public returns (uint256) {
        updateNeutralAsset();

        // conditions
        if (amount_ == 0) {
            return 0;
        }

        // get _usdc
        _usdc.safeTransferFrom(msg.sender, address(this), amount_);

        // deposit
        _neutral.deposit(amount_);

        // mint
        uint256 amount;
        if (totalSupply() == 0) {
            amount = amount_;
        } else {
            amount = (totalSupply() * amountToValue(amount_)) / totalValue();
        }
        _mint(account_, amount);

        return amount;
    }

    function burn(address account_, uint256 amount_) public returns (uint256) {
        updateNeutralAsset();

        // conditions
        if (amount_ == 0) {
            return 0;
        }
        require(totalSupply() != 0, "Share::burn: invalid request");

        // burn
        uint256 amount;
        amount = (totalSupply() * amountToValue(amount_)) / totalValue();
        _burn(account_, amount);

        // withdraw
        _neutral.withdraw(amount);

        // send _usdc
        _usdc.safeTransfer(msg.sender, amount);

        return amount;
    }

    //============= VIEW FUNCTIONS =============//

    function neutral() view external returns (address){
        return address(_neutral);
    }

    function usdc() view external returns (address){
        return address(_usdc);
    }

    function amountToValue(uint256 amount) public returns (uint256) {
        return amount; // now, only _usdc
    }

    function totalValue() public view returns (uint256) {
        return _neutral.assetTotalValue();
    }

    function valueOf(address account) public view returns (uint256) {
        return (totalValue() * balanceOf(account)) / totalSupply();
    }

    //============= UPDATE ASSETS ==============//

    function updateNeutralAsset() public {
        _neutral.updateDebtInfo(0, 0);
        _neutral.updateCollateralInfo(0, 0);
    }

    function accurateValueOf(address account) public returns (uint256) {
        updateNeutralAsset();
        return (totalValue() * balanceOf(account)) / totalSupply();
    }
}
