pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import './libraries/UniswapV2OracleLibrary.sol';
import './libraries/UniswapV2Library.sol';

import './interfaces/IERC20.sol';
import './interfaces/IMostERC20.sol';
import './interfaces/IMostOracle.sol';

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract MostOracle is IMostOracle {
    using FixedPoint for *;
    using SafeMath for uint;
    using SafeMath for int;

    uint public constant override PERIOD = 24 hours;

    address public override immutable pair;
    address public override immutable token0;
    address public override immutable token1;
    address public override immutable mostToken;

    uint    public override price0CumulativeLast;
    uint    public override price1CumulativeLast;
    uint32  public override blockTimestampLast;
    FixedPoint.uq112x112 private price0Average;
    FixedPoint.uq112x112 private price1Average;

    uint8 private constant RATE_BASE = 100;
    uint8 private constant UPPER_BOUND = 106;
    uint8 private constant LOWER_BOUND = 96;
    uint private constant MAX_SUPPLY = 1 * 10**9 * 10**uint(9);  // 1 billion mBTC

    constructor(address factory, address _mostToken, address _baseToken) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, _mostToken, _baseToken));
        pair = address(_pair);
        token0 = _pair.token0();
        token1 = _pair.token1();
        mostToken = _mostToken;
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'MostOracle: NO_RESERVES'); // ensure that there's liquidity in the pair
    }

    function update() external override {
        require(msg.sender == mostToken, 'MostOracle: FORBIDDEN'); // sufficient check

        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, 'MostOracle: PERIOD_NOT_ELAPSED');

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint amountIn) external view override returns (uint amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, 'MostOracle: INVALID_TOKEN');
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }

    function consultNow(uint amountIn) external view override returns (uint amountOut, int256 supplyDelta, uint totalSupply) {
        IMostERC20 mostERC20Token = IMostERC20(mostToken);

        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        uint priceAverage;
        uint tokenBRemaining;

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        if (mostToken == token0) {
            FixedPoint.uq112x112 memory _price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
            amountOut = _price0Average.mul(amountIn).decode144();
            priceAverage = _price0Average.mul(10 ** uint(mostERC20Token.decimals())).decode144();
            tokenBRemaining = 10 ** uint(IERC20(token1).decimals() - 2);
        } else {
            require(mostToken == token1, 'MOST: INVALID_TOKEN');
            FixedPoint.uq112x112 memory _price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));
            amountOut = _price1Average.mul(amountIn).decode144();
            priceAverage = _price1Average.mul(10 ** uint(mostERC20Token.decimals())).decode144();
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
}
