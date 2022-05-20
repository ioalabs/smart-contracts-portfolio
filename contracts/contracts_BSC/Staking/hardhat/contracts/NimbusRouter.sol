// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract NimbusRouter {
    uint256 public multiplier = 10;

    constructor() {}

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[1] = amountIn * multiplier;
    }

    function setMultiplier(uint256 _multiplier) external {
        multiplier = _multiplier;
    }
}