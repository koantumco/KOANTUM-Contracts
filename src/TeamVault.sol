// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Immutable time vault for KOANTUM team tokens.
/// @dev Generic ERC20 release avoids a deployment circular dependency with KOANT.
contract TeamVault {
    using SafeERC20 for IERC20;

    error ZeroBeneficiary();
    error InvalidUnlockTime();
    error TooEarly(uint256 currentTime, uint256 unlockTime);
    error NothingToRelease();

    address public immutable beneficiary;
    uint256 public immutable unlockTime;

    event Released(address indexed token, address indexed beneficiary, uint256 amount);

    constructor(address beneficiary_, uint256 unlockTime_) {
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        if (unlockTime_ <= block.timestamp) revert InvalidUnlockTime();
        beneficiary = beneficiary_;
        unlockTime = unlockTime_;
    }

    function releaseToken(IERC20 token) external {
        if (block.timestamp < unlockTime) revert TooEarly(block.timestamp, unlockTime);
        uint256 amount = token.balanceOf(address(this));
        if (amount == 0) revert NothingToRelease();
        token.safeTransfer(beneficiary, amount);
        emit Released(address(token), beneficiary, amount);
    }
}
