// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockV2Router {
    address public immutable factory;
    address public immutable WETH;
    uint256 public ethOutPerSwap;

    constructor(address factory_, address weth_) {
        factory = factory_;
        WETH = weth_;
    }

    receive() external payable {}

    function setEthOutPerSwap(uint256 amount) external {
        ethOutPerSwap = amount;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 out = ethOutPerSwap;
        require(address(this).balance >= out, "mock router lacks ETH");
        (bool ok,) = payable(to).call{value: out}("");
        require(ok, "ETH send failed");
    }
}
