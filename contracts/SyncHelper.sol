pragma solidity =0.6.6;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

contract SyncHelper is Ownable {
    using SafeERC20 for IERC20;

    function transferAndSync(IERC20 token, address to, uint256 value, bool shouldSync) public onlyOwner {
        uint256 amount = token.balanceOf(address(this));
        require(amount >= value, "SyncHelper: no enough tokens to release");

        token.safeTransfer(to, value);
        if (shouldSync) {
            IUniswapV2Pair(to).sync();
        }
    }
}
