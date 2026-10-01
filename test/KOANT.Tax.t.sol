// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {KOANT} from "../src/KOANT.sol";
import {MockV2Router} from "./mocks/MockV2Router.sol";
import {MockV2Pair} from "./mocks/MockV2Pair.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract KOANTTaxTest is Test {
    MockERC20 wethToken;
    address weth;

    address treasury = makeAddr("treasury");
    address founder1 = makeAddr("founder1");
    address founder2 = makeAddr("founder2");
    address genesisSafe = makeAddr("genesisSafe");
    address teamVault = makeAddr("teamVault");
    address factory = makeAddr("factory");

    KOANT token;
    MockV2Router router;
    MockV2Pair pair;

    function setUp() public {
        wethToken = new MockERC20("Wrapped Ether", "WETH");
        weth = address(wethToken);
        router = new MockV2Router(factory, address(weth));
        token = new KOANT(treasury, founder1, founder2, genesisSafe, teamVault, address(router), 40_469_000 ether);
        pair = new MockV2Pair(factory, address(weth), address(token));
        vm.prank(treasury);
        token.initializePair(address(pair));
        vm.prank(genesisSafe);
        token.transfer(address(pair), 20_000_000_000 ether);
        vm.prank(treasury);
        token.enableTrading();
    }

    function _buy(address user, uint256 amount) internal {
        pair.sendToken(address(token), user, amount);
    }

    function test_Buy69Taxed_Buy70Untaxed() public {
        for (uint256 i = 0; i < 69; ++i) {
            address user = address(uint160(0x1000 + i));
            _buy(user, 100 ether);
            assertEq(token.balanceOf(user), 99 ether);
        }
        assertEq(token.buyCount(), 69);

        address user70 = address(0x7777);
        _buy(user70, 100 ether);
        assertEq(token.balanceOf(user70), 100 ether);
        assertEq(token.buyCount(), 70);
    }

    function test_SellTaxEndsAfterBuy404() public {
        address seller = makeAddr("seller");
        _buy(seller, 1_000 ether); // buy #1, seller receives 990

        for (uint256 i = 1; i < 404; ++i) {
            address user = address(uint160(0x2000 + i));
            _buy(user, 1 ether);
        }
        assertEq(token.buyCount(), 404);
        assertEq(token.activeSellTaxBps(), 0);

        uint256 pairBefore = token.balanceOf(address(pair));
        vm.prank(seller);
        token.transfer(address(pair), 100 ether);
        assertEq(token.balanceOf(address(pair)) - pairBefore, 100 ether);
    }
}
