// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {KOANT} from "../src/KOANT.sol";
import {MockV2Router} from "./mocks/MockV2Router.sol";

contract KOANTAllocationTest is Test {
    address treasury = makeAddr("treasury");
    address founder1 = makeAddr("founder1");
    address founder2 = makeAddr("founder2");
    address genesisSafe = makeAddr("genesisSafe");
    address teamVault = makeAddr("teamVault");
    address factory = makeAddr("factory");
    address weth = makeAddr("weth");

    KOANT token;
    MockV2Router router;

    function setUp() public {
        router = new MockV2Router(factory, weth);
        token = new KOANT(treasury, founder1, founder2, genesisSafe, teamVault, address(router), tokenMinThreshold());
    }

    function tokenMinThreshold() internal pure returns (uint256) {
        return 40_469_000 ether;
    }

    function test_AllocationAndSupplyAreExact() public view {
        assertEq(token.totalSupply(), 404_690_000_000 ether);
        assertEq(token.balanceOf(founder1), 6_070_350_000 ether);
        assertEq(token.balanceOf(founder2), 6_070_350_000 ether);
        assertEq(token.balanceOf(teamVault), 15_782_910_000 ether);
        assertEq(token.balanceOf(genesisSafe), 376_766_390_000 ether);
        assertEq(token.balanceOf(treasury), 0);
    }
}
