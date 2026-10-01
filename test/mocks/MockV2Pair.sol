// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMintableERC20 {
    function mint(address to, uint256 amount) external;
}

contract MockV2Pair {
    error InvalidOutputToken();

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    constructor(address factory_, address token0_, address token1_) {
        factory = factory_;
        token0 = token0_;
        token1 = token1_;
    }

    function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    function setReserves(uint112 reserve0_, uint112 reserve1_) external {
        reserve0 = reserve0_;
        reserve1 = reserve1_;
        blockTimestampLast = uint32(block.timestamp);
    }

    function sync() public {
        _sync();
    }

    // Test helper for a swap-like Pair -> wallet KOANT transfer.
    // The opposite token is treated as the swap input token.
    function sendToken(address token, address to, uint256 amount) external {
        address inputToken;

        if (token == token0) {
            inputToken = token1;
        } else if (token == token1) {
            inputToken = token0;
        } else {
            revert InvalidOutputToken();
        }

        // Record the pre-swap reserves first.
        _sync();

        // Simulate the V2 ordering relevant to KOANT's detector:
        // input token reaches Pair before output token leaves Pair.
        IMintableERC20(inputToken).mint(address(this), 1 ether);

        IERC20(token).transfer(to, amount);

        // Real V2 Pair updates reserves after the output transfer.
        _sync();
    }

    // Raw Pair outflow used for skim/liquidity-removal style tests.
    // No input token is added and reserves are intentionally not updated.
    function skimToken(address token, address to, uint256 amount) external {
        IERC20(token).transfer(to, amount);
    }

    function _sync() internal {
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
        blockTimestampLast = uint32(block.timestamp);
    }
}
