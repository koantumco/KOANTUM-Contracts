// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TeamVault} from "../src/TeamVault.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract TeamVaultTest is Test {
    address treasury = makeAddr("treasury");
    address caller = makeAddr("caller");
    uint256 unlock;
    TeamVault vault;
    MockToken token;

    function setUp() public {
        unlock = block.timestamp + 365 days;
        vault = new TeamVault(treasury, unlock);
        token = new MockToken();
        token.transfer(address(vault), 100 ether);
    }

    function test_RevertBeforeUnlock() public {
        vm.expectRevert();
        vm.prank(caller);
        vault.releaseToken(IERC20(address(token)));
    }

    function test_PermissionlessReleaseToTreasuryAtUnlock() public {
        vm.warp(unlock);
        vm.prank(caller);
        vault.releaseToken(IERC20(address(token)));
        assertEq(token.balanceOf(treasury), 100 ether);
        assertEq(token.balanceOf(caller), 0);
    }
}
