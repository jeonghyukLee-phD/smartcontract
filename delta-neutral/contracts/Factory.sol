// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./NeutralV2.sol";
import "./interfaces/INeutralV2.sol";
import "hardhat/console.sol";

contract Factory is Ownable {
    mapping(uint256 => address) internal _strategies;
    uint256 public position_len;

    constructor(address initialOwner) Ownable(initialOwner){}

    function getStrategy(uint256 key) external view returns (address) {
        return _strategies[key];
    }

    /**
     * @param key TBD
     */
    function createNeutral(uint256 key)
        external
        onlyOwner
        returns (address strategy)
    {
        require(
            _strategies[key] == address(0),
            "Factory::createNeutral: already exists."
        );

        // bytes memory bytecode = type(Neutral).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(key));
        // assembly {
        //     strategy := create2(0, add(bytecode, 32), mload(bytecode), salt)
        // }
        strategy = address(new NeutralV2{salt: salt}(owner()));
        // emit // TODO
        _strategies[key] = strategy;
        position_len++;
    }

    function initialize_1(
        uint256 key,
        address stb_asset,
        address vrb_asset,
        address reward_asset,
        uint256 vrb_weight,
        uint256 collateral_rate
    ) external onlyOwner {
        INeutralV2(_strategies[key]).initialize_1(
            stb_asset,
            vrb_asset,
            reward_asset,
            vrb_weight,
            collateral_rate
        );
    }

    function initialize_2(
        uint256 key,
        address router,
        address farm,
        address lp,
        uint256 pid,
        address aToken,
        address pool,
        address owner
    ) external onlyOwner {
        INeutralV2(_strategies[key]).initialize_2(
            router,
            farm,
            lp,
            pid,
            aToken,
            pool,
            owner
        );
    }

    function initialize_3(uint256 key, address pair) external onlyOwner {
        INeutralV2(_strategies[key]).setCapitalPrice(pair);
    }

    function initialize_4(uint256 key, address pair) external onlyOwner {
        INeutralV2(_strategies[key]).setRewardPrice(pair);
    }

    function setStrategist(uint256 key, address strategist) external onlyOwner {
        INeutralV2(_strategies[key]).setStrategist(strategist);
    }

    function getPositionNum() external view returns (uint256) {
        return position_len;
    }
}
