// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

interface IFactory{
    
    function getStrategy(uint256 key) external view returns (address);
    function getPositionNum() external view returns (uint256);
}