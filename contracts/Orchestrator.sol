pragma solidity =0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import './libraries/UniswapV2OracleLibrary.sol';
import './libraries/SafeMath.sol';
import './interfaces/IMostERC20.sol';
import './interfaces/IERC20.sol';

/**
 * @title Orchestrator
 * @notice The orchestrator is the main entry point for rebase operations. It coordinates the mostToken
 * actions with external consumers.
 */
contract Orchestrator is Ownable {
    using FixedPoint for *;
    using SafeMath for uint;
    using SafeMath for int;

    uint8 private constant RATE_BASE = 100;
    uint8 private constant UPPER_BOUND = 106;
    uint8 private constant LOWER_BOUND = 96;
    uint private constant MAX_SUPPLY = ~uint128(0);  // (2^128) - 1

    struct Transaction {
        bool enabled;
        address destination;
        bytes data;
    }

    event TransactionFailed(address indexed destination, uint index, bytes data);

    // Stable ordering is not guaranteed.
    Transaction[] public transactions;

    address public mostToken;

    /**
     * @param _mostToken Address of the UFragments mostToken.
     */
    constructor(address _mostToken) public {
        mostToken = _mostToken;
    }

    /**
     * @notice Main entry point to initiate a rebase operation.
     *         The Orchestrator calls rebase on the mostToken and notifies downstream applications.
     *         Contracts are guarded from calling, to avoid flash loan attacks on liquidity
     *         providers.
     *         If a transaction in the transaction list reverts, it is swallowed and the remaining
     *         transactions are executed.
     */
    function rebase()
        external
    {
        require(msg.sender == tx.origin);  // solhint-disable-line avoid-tx-origin

        IMostERC20(mostToken).rebase();

        for (uint i = 0; i < transactions.length; i++) {
            Transaction storage t = transactions[i];
            if (t.enabled) {
                (bool result, ) = address(t.destination).call(t.data);
                if (!result) {
                    emit TransactionFailed(t.destination, i, t.data);
                    revert("Transaction Failed");
                }
            }
        }
    }

    /**
     * @notice Adds a transaction that gets called for a downstream receiver of rebases
     * @param destination Address of contract destination
     * @param data Transaction data payload
     */
    function addTransaction(address destination, bytes calldata data)
        external
        onlyOwner
    {
        transactions.push(Transaction({
            enabled: true,
            destination: destination,
            data: data
        }));
    }

    /**
     * @param index Index of transaction to remove.
     *              Transaction ordering may have changed since adding.
     */
    function removeTransaction(uint index)
        external
        onlyOwner
    {
        require(index < transactions.length, "index out of bounds");

        if (index < transactions.length - 1) {
            transactions[index] = transactions[transactions.length - 1];
        }

        transactions.pop();
    }

    /**
     * @param index Index of transaction. Transaction ordering may have changed since adding.
     * @param enabled True for enabled, false for disabled.
     */
    function setTransactionEnabled(uint index, bool enabled)
        external
        onlyOwner
    {
        require(index < transactions.length, "index must be in range of stored tx list");
        transactions[index].enabled = enabled;
    }

    /**
     * @return Number of transactions, both enabled and disabled, in transactions list.
     */
    function transactionsSize()
        external
        view
        returns (uint256)
    {
        return transactions.length;
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
}