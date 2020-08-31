pragma solidity >=0.6.2;

interface IMostOracle {
    function PERIOD() external pure returns (uint);

    function pair() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function mostToken() external view returns (address);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function blockTimestampLast() external view returns (uint32);
    function update() external;
    function consult(address token, uint amountIn) external view returns (uint amountOut);
    function consultNow(uint amountIn) external view returns (uint amountOut, int256 supplyDelta, uint totalSupply);
}
