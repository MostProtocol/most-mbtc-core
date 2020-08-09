pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import './libraries/UniswapV2OracleLibrary.sol';
import './libraries/SafeMath.sol';
import './interfaces/IMostERC20.sol';
import './interfaces/IERC20.sol';

contract MostHelper {
    using FixedPoint for *;
    using SafeMath for uint;
    using SafeMath for int;

    uint8 private constant RATE_BASE = 100;
    uint8 private constant UPPER_BOUND = 106;
    uint8 private constant LOWER_BOUND = 96;
    uint private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

    address pair;
    address mostToken;

    constructor(address _pair, address _mostToken) public {
        pair = _pair;
        mostToken = _mostToken;
    }

    function consultNow(uint amountIn) external view returns (uint amountOut, int256 supplyDelta, uint totalSupply) {
        IMostERC20 mostERC20Token = IMostERC20(mostToken);
        address token0 = mostERC20Token.token0();
        address token1 = mostERC20Token.token1();

        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(mostERC20Token.pair());
        uint32 timeElapsed = blockTimestamp - mostERC20Token.blockTimestampLast(); // overflow is desired

        uint priceAverage;
        uint tokenBRemaining;

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        if (mostToken == token0) {
            FixedPoint.uq112x112 memory price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - mostERC20Token.price0CumulativeLast()) / timeElapsed));
            amountOut = price0Average.mul(amountIn).decode144();
            priceAverage = price0Average.mul(10 ** uint(mostERC20Token.decimals())).decode144();
            tokenBRemaining = 10 ** uint(IERC20(token1).decimals() - 2);
        } else {
            require(mostToken == token1, 'MOST: INVALID_TOKEN');
            FixedPoint.uq112x112 memory price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - mostERC20Token.price1CumulativeLast()) / timeElapsed));
            amountOut = price1Average.mul(amountIn).decode144();
            priceAverage = price1Average.mul(10 ** uint(mostERC20Token.decimals())).decode144();
            tokenBRemaining = 10 ** uint(IERC20(token0).decimals() - 2);
        }

        uint unitBase = RATE_BASE * tokenBRemaining;
        if (priceAverage > UPPER_BOUND * tokenBRemaining) {
            supplyDelta = 0 - int(mostERC20Token.totalSupply().mul(priceAverage.sub(unitBase)) / priceAverage);
        } else if (priceAverage < LOWER_BOUND * tokenBRemaining) {
            supplyDelta = int(mostERC20Token.totalSupply().mul(unitBase.sub(priceAverage)) / unitBase);
        } else {
            supplyDelta = 0;
        }

        supplyDelta = supplyDelta / 10;

        if (supplyDelta == 0) {
            totalSupply = mostERC20Token.totalSupply();
        }

        if (supplyDelta < 0) {
            totalSupply = mostERC20Token.totalSupply().sub(uint256(supplyDelta.abs()));
        } else {
            totalSupply = mostERC20Token.totalSupply().add(uint256(supplyDelta));
        }

        if (totalSupply > MAX_SUPPLY) {
            totalSupply = MAX_SUPPLY;
        }
    }

    function rebase() external returns (uint totalSupply) {
        totalSupply = IMostERC20(mostToken).rebase();
        IUniswapV2Pair(pair).sync();
    }
}
