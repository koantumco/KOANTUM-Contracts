// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Immutable lock for the official KOANT/WETH Uniswap V2 LP token.
contract LPLocker {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidUnlockTime();
    error TooEarly(uint256 currentTime, uint256 unlockTime);
    error NothingToRelease();

    IERC20 public immutable lpToken;
    address public immutable beneficiary;
    uint256 public immutable unlockTime;

    event Released(address indexed lpToken, address indexed beneficiary, uint256 amount);

    constructor(IERC20 lpToken_, address beneficiary_, uint256 unlockTime_) {
        if (address(lpToken_) == address(0) || beneficiary_ == address(0)) revert ZeroAddress();
        if (unlockTime_ <= block.timestamp) revert InvalidUnlockTime();
        lpToken = lpToken_;
        beneficiary = beneficiary_;
        unlockTime = unlockTime_;
    }

    function release() external {
        if (block.timestamp < unlockTime) revert TooEarly(block.timestamp, unlockTime);
        uint256 amount = lpToken.balanceOf(address(this));
        if (amount == 0) revert NothingToRelease();
        lpToken.safeTransfer(beneficiary, amount);
        emit Released(address(lpToken), beneficiary, amount);
    }
}
