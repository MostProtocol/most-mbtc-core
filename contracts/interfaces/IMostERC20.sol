pragma solidity >=0.6.2;

interface IMostERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);
    event LogRebase(uint indexed epoch, uint totalSupply);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function epoch() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function oracle() external view returns (address);
    function rebaseSetter() external view returns (address);
    function creator() external view returns (address);
    function initialize(address) external;
    function rebase() external returns (uint);
    function setRebaseSetter(address) external;
    function setCreator(address) external;
}
