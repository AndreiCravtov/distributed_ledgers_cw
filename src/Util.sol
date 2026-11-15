// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

library Util {
    AggregatorV3Interface public constant ETH_USDC = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    /// Converts USDC to ETH, both scaled to 18 decimal points
    /// @param usdc_18x USDC to be converted, scaled to 18 decimal points
    function usdcToEth_18x(uint256 usdc_18x) public view returns (uint256) {
        // 1 ETH : price USD*10^decimal
        (, int256 answer,,,) = ETH_USDC.latestRoundData(); // 1 ETH = this many USDC (in the decimals above)
        require(answer > 0, "Invalid oracle price");
        uint256 price = uint256(answer);

        // compute ETH to 18 decimal points
        return (usdc_18x * 10 ** ETH_USDC.decimals()) / price;
    }
}
