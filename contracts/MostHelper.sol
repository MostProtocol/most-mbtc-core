pragma solidity =0.6.6;

import './interfaces/IMostERC20.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import './libraries/UniswapV2OracleLibrary.sol';
import './libraries/UniswapV2Library.sol';
import './interfaces/IMostERC20.sol';

contract MostHelper {
    using FixedPoint for *;
    using SafeMath for uint;
    using SafeMath for int;

    uint8 private constant RATE_BASE = 100;
    uint8 private constant UPPER_BOUND = 106;
    uint8 private constant LOWER_BOUND = 96;
    uint private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

    function consultNow(address factory, address tokenA, address tokenB, uint amountAIn) external view returns (uint amountBOut, int256 supplyDelta, uint totalSupply) {
        IMostERC20 mostTokenA = IMostERC20(tokenA);
        IMostERC20 mostTokenB = IMostERC20(tokenB);
        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(_pair));
        uint32 timeElapsed = blockTimestamp - mostTokenA.blockTimestampLast(); // overflow is desired

        uint priceAverage;

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        if (tokenA == mostTokenA.token0()) {
            FixedPoint.uq112x112 memory price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - mostTokenA.price0CumulativeLast()) / timeElapsed));
            amountBOut = price0Average.mul(amountAIn).decode144();
            priceAverage = price0Average.mul(10 ** uint(mostTokenA.decimals())).decode144();
        } else {
            require(tokenA == mostTokenA.token1(), 'MOST: INVALID_TOKEN');
            FixedPoint.uq112x112 memory price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - mostTokenA.price1CumulativeLast()) / timeElapsed));
            amountBOut = price1Average.mul(amountAIn).decode144();
            priceAverage = price1Average.mul(10 ** uint(mostTokenA.decimals())).decode144();
        }

        uint unitBase = RATE_BASE * 10 ** uint(mostTokenB.decimals() - 2);
        if (priceAverage > UPPER_BOUND * 10 ** uint(mostTokenB.decimals() - 2)) {
            supplyDelta = 0 - int(mostTokenA.totalSupply().mul(priceAverage.sub(unitBase)) / priceAverage);
        } else if (priceAverage < LOWER_BOUND * 10 ** uint(mostTokenB.decimals() - 2)) {
            supplyDelta = int(mostTokenA.totalSupply().mul(unitBase.sub(priceAverage)) / unitBase);
        } else {
            supplyDelta = 0;
        }

        supplyDelta = supplyDelta / 10;

        if (supplyDelta == 0) {
            totalSupply = mostTokenA.totalSupply();
        }

        if (supplyDelta < 0) {
            totalSupply = mostTokenA.totalSupply().sub(uint256(supplyDelta.abs()));
        } else {
            totalSupply = mostTokenA.totalSupply().add(uint256(supplyDelta));
        }

        if (totalSupply > MAX_SUPPLY) {
            totalSupply = MAX_SUPPLY;
        }
    }
}
