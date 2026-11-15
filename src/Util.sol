// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IWETH9} from "@/IWETH9.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IPeripheryImmutableState} from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";

library Util {
    uint256 public constant SLIPPAGE_PERCENT = 2;
    AggregatorV3Interface public constant ETH_USDC = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
    IERC20Metadata public constant USDC = IERC20Metadata(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
    IWETH9 public constant WETH9 = IWETH9(0x4200000000000000000000000000000000000006);
    ISwapRouter public constant UNISWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

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

    /// Converts USDC scaled by 18 decimal points, to its native scale (i.e. 6 decimal points)
    /// and a remainder for the fraction that was truncated, scaled to 18 decimal points.
    /// @param usdc_18x USDC amount scaled by 18 decimal points
    /// @return USDC amount scaled to native amount of decimal points (i.e. 6)
    /// @return USDC remainder that was truncated during conversion, scaled by 18 decimal points
    function usdc18x_toNative(uint256 usdc_18x) public view returns (uint256, uint256) {
        // as per spec: sanity check USDC has <=18 decimal places (i.e. 6)
        uint256 decimals = USDC.decimals();
        require(decimals <= 18, "USDC contract has invalid decimals");

        // convert & get remainder
        uint256 scale = 10 ** (18 - decimals);
        uint256 usdc = usdc_18x / scale;
        uint256 rem_x18 = usdc_18x % scale;
        return (usdc, rem_x18);
    }

    /// Converts USDC scaled to its native scale (i.e. 6 decimal points), to 18x scaling.
    /// @param usdc USDC amount scaled to native amount of decimal points (i.e. 6)
    function usdcNative_to18x(uint256 usdc) public view returns (uint256) {
        // as per spec: sanity check USDC has <=18 decimal places (i.e. 6)
        uint256 decimals = USDC.decimals();
        require(decimals <= 18, "USDC contract has invalid decimals");

        return usdc * 10 ** (18 - decimals);
    }

    function discoverPoolFee_UsdcWeth9(uint24[] memory feeCandidates) public view returns (address, uint24) {
        IUniswapV3Factory factory = IUniswapV3Factory(IPeripheryImmutableState(address(Util.UNISWAP_ROUTER)).factory());

        // range over fee candidates, to find the one with largest liquidity
        address selectedPool;
        uint24 selectedFee;
        uint128 largestLiquidity;

        for (uint256 i; i < feeCandidates.length; i++) {
            address candidate = factory.getPool(address(Util.USDC), address(Util.WETH9), feeCandidates[i]);

            if (candidate == address(0)) continue;

            uint128 liquidity = IUniswapV3Pool(candidate).liquidity();

            if (liquidity > largestLiquidity) {
                selectedPool = candidate;
                selectedFee = feeCandidates[i];
                largestLiquidity = liquidity;
            }
        }

        require(selectedPool != address(0), "Could not find liquid pool for salary conversion");
        return (selectedPool, selectedFee);
    }
}
