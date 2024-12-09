// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

interface IShare {
    event changeNeutral(address oldNeutral, address newNeutral);
    event changeUSDC(address oldUSDC, address newUSDC);
    
    function neutral() view external returns (address);
    function usdc() view external returns (address);

    function setNeutral(address newNeutral) external;
    function setUsdc(address newUsdc) external;
    function mint(address account_, uint256 amount_) external returns (uint256);
    function burn(address account_, uint256 amount_) external returns (uint256);
    function amountToValue(uint256 amount) external returns (uint256);
    function totalValue() external view returns (uint256);
    function valueOf(address account) external view returns (uint256);
    function updateNeutralAsset() external;
    function accurateValueOf(address account) external returns (uint256);
}
