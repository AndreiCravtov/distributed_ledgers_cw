// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Counter} from "@/Counter.sol";
import {IWETH9} from "@/IWETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

contract CounterScript is Script {
    AggregatorV3Interface public constant ETH_USD = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
    ISwapRouter public constant UNISWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC20 public constant USDC = IERC20(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
    IWETH9 public constant WETH9 = IWETH9(0x4200000000000000000000000000000000000006);

    Counter public counter;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // ETH/USDC chainlink data aggregator
        uint8 decimals = ETH_USD.decimals(); // always check answer
        (, int256 answer,,,) = ETH_USD.latestRoundData(); // 1 ETH = this many USDC (in the decimals above)

        // SEE: https://developers.uniswap.org/docs/protocols/v3/guides/swapping/single-hop-swapping
        // For this example, we will set the pool fee to 0.3%.
        uint24 poolFee = 3000;
        UNISWAP_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(USDC),
                tokenOut: address(WETH9),
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: 10,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        counter = new Counter();

        vm.stopBroadcast();
    }
}
