// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LPLocker} from "../src/LPLocker.sol";

contract MockLP is ERC20 {
    constructor() ERC20("LP", "LP") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract LPLockerTest is Test {
    address genesisSafe = makeAddr("genesisSafe");
    address caller = makeAddr("caller");
    uint256 unlock;
    LPLocker locker;
    MockLP lp;

    function setUp() public {
        unlock = block.timestamp + 365 days;
        lp = new MockLP();
        locker = new LPLocker(IERC20(address(lp)), genesisSafe, unlock);
        lp.transfer(address(locker), 100 ether);
    }

    function test_RevertBeforeUnlock() public {
        vm.expectRevert();
        vm.prank(caller);
        locker.release();
    }

    function test_PermissionlessReleaseToGenesisSafeAtUnlock() public {
        vm.warp(unlock);
        vm.prank(caller);
        locker.release();
        assertEq(lp.balanceOf(genesisSafe), 100 ether);
        assertEq(lp.balanceOf(caller), 0);
    }
}
