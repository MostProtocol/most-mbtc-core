pragma solidity =0.6.6;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import "@openzeppelin/contracts/access/Ownable.sol";

contract MultipleTokenTimeLock is Ownable {
    using SafeERC20 for IERC20;

    // beneficiary of tokens after they are released
    address private _beneficiary;

    // timestamp when token release is enabled
    uint256 private _releaseTime;

    constructor (address beneficiary, uint256 releaseTime) public {
        // solhint-disable-next-line not-rely-on-time
        require(releaseTime > block.timestamp, "MultipleTokenTimeLock: release time is before current time");
        _beneficiary = beneficiary;
        _releaseTime = releaseTime;
    }

    /**
     * @return the beneficiary of the tokens.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the time when the tokens are released.
     */
    function releaseTime() public view returns (uint256) {
        return _releaseTime;
    }

    function newReleaseTime(uint period) public onlyOwner {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp >= _releaseTime, "MultipleTokenTimeLock: current time is before release time");
        require(period <= 1000 days, "MultipleTokenTimeLock: release time cannot be longer than 1000 days");
        require(period > 0, "MultipleTokenTimeLock: release time cannot be 0");

        _releaseTime = _releaseTime + period;
    }

    /**
     * @notice Transfers tokens held by timelock to beneficiary.
     */
    function release(IERC20 token) public {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp >= _releaseTime, "MultipleTokenTimeLock: current time is before release time");

        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "MultipleTokenTimeLock: no tokens to release");

        token.safeTransfer(_beneficiary, amount);
    }
}
