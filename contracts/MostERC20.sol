pragma solidity =0.6.6;

import './interfaces/IMostERC20.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/lib/contracts/libraries/FixedPoint.sol';

import './libraries/UniswapV2OracleLibrary.sol';
import './libraries/UniswapV2Library.sol';

contract MostERC20 is IMostERC20 {
    using FixedPoint for *;
    using SafeMath for uint;
    using SafeMath for int;

    string public constant override name = 'MOST';
    string public constant override symbol = 'MOST';
    uint8 public constant override decimals = 9;
    uint public override totalSupply;
    uint public override epoch;
    mapping(address => uint) private gonBalanceOf;
    mapping(address => mapping(address => uint)) public override allowance;

    uint public constant override PERIOD = 24 hours;

    uint private constant MAX_UINT256 = ~uint256(0);
    uint private constant INITIAL_FRAGMENTS_SUPPLY = 1 * 10**6 * 10**uint(decimals);
    uint8 private constant RATE_BASE = 100;
    uint8 private constant UPPER_BOUND = 106;
    uint8 private constant LOWER_BOUND = 96;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

    uint private gonsPerFragment;

    IUniswapV2Pair pair;
    address public override creator;
    address public override token0;
    address public override token1;

    uint public override price0CumulativeLast;
    uint public override price1CumulativeLast;
    uint32 public override blockTimestampLast;
    FixedPoint.uq112x112 private price0Average;
    FixedPoint.uq112x112 private price1Average;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);
    event LogRebase(uint indexed epoch, uint totalSupply);

    constructor() public {
        creator = msg.sender;

        totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        gonBalanceOf[msg.sender] = TOTAL_GONS;
        gonsPerFragment = TOTAL_GONS / totalSupply;

        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function initialize(address factory, address tokenB) external override {
        require(msg.sender == creator, 'MOST: FORBIDDEN'); // sufficient check

        IUniswapV2Pair _pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, address(this), tokenB));
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'MOST: NO_RESERVES'); // ensure that there's liquidity in the pair

        creator = address(0);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        uint gonValue = value.mul(gonsPerFragment);
        gonBalanceOf[from] = gonBalanceOf[from].sub(gonValue);
        gonBalanceOf[to] = gonBalanceOf[to].add(gonValue);
        emit Transfer(from, to, value);
    }

    function balanceOf(address owner) external view override returns (uint) {
        return gonBalanceOf[owner] / gonsPerFragment;
    }

    function approve(address spender, uint value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external override returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    function rebase() external override returns (uint)
    {
        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, 'MOST: PERIOD_NOT_ELAPSED');

        epoch = epoch.add(1);

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;

        uint priceAverage = consult(address(this), 10**uint(decimals));

        uint tokenBDecimals;
        if (address(this) == token0) {
            tokenBDecimals = IMostERC20(token1).decimals();
        } else {
            tokenBDecimals = IMostERC20(token0).decimals();
        }
        uint unitBase = RATE_BASE * 10 ** (tokenBDecimals - 2);
        int256 supplyDelta;
        if (priceAverage > UPPER_BOUND * 10 ** (tokenBDecimals - 2)) {
            supplyDelta = 0 - int(totalSupply.mul(priceAverage.sub(unitBase)) / priceAverage);
        } else if (priceAverage < LOWER_BOUND * 10 ** (tokenBDecimals - 2)) {
            supplyDelta = int(totalSupply.mul(unitBase.sub(priceAverage)) / unitBase);
        } else {
            supplyDelta = 0;
        }

        supplyDelta = supplyDelta / 10;

        if (supplyDelta == 0) {
            emit LogRebase(epoch, totalSupply);
            return totalSupply;
        }

        if (supplyDelta < 0) {
            totalSupply = totalSupply.sub(uint256(supplyDelta.abs()));
        } else {
            totalSupply = totalSupply.add(uint256(supplyDelta));
        }

        if (totalSupply > MAX_SUPPLY) {
            totalSupply = MAX_SUPPLY;
        }

        gonsPerFragment = TOTAL_GONS / totalSupply;

        // From this point forward, gonsPerFragment is taken as the source of truth.
        // We recalculate a new totalSupply to be in agreement with the gonsPerFragment
        // conversion rate.
        // This means our applied supplyDelta can deviate from the requested supplyDelta,
        // but this deviation is guaranteed to be < (totalSupply^2)/(TOTAL_GONS - totalSupply).
        //
        // In the case of totalSupply <= MAX_UINT128 (our current supply cap), this
        // deviation is guaranteed to be < 1, so we can omit this step. If the supply cap is
        // ever increased, it must be re-included.
        // totalSupply = TOTAL_GONS / gonsPerFragment

        emit LogRebase(epoch, totalSupply);
        return totalSupply;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint amountIn) public view override returns (uint amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, 'MOST: INVALID_TOKEN');
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
