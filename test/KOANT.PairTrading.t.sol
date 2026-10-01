// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {KOANT} from "../src/KOANT.sol";
import {MockV2Router} from "./mocks/MockV2Router.sol";
import {MockV2Pair} from "./mocks/MockV2Pair.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract KOANTPairTradingTest is Test {
    address treasury = makeAddr("treasury");
    address founder1 = makeAddr("founder1");
    address founder2 = makeAddr("founder2");
    address genesisSafe = makeAddr("genesisSafe");
    address teamVault = makeAddr("teamVault");
    address factory = makeAddr("factory");
    MockERC20 weth;
    address alice = makeAddr("alice");

    KOANT token;
    MockV2Router router;
    MockV2Pair pair;

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH");
        router = new MockV2Router(factory, address(weth));

        token = new KOANT(treasury, founder1, founder2, genesisSafe, teamVault, address(router), 40_469_000 ether);

        pair = new MockV2Pair(factory, address(weth), address(token));

        vm.prank(treasury);
        token.initializePair(address(pair));

        vm.prank(genesisSafe);
        token.transfer(address(pair), 10_000_000_000 ether);
    }

    function test_NonTreasuryCannotInitializePair() public {
        vm.expectRevert(KOANT.NotTreasury.selector);
        vm.prank(alice);
        token.initializePair(address(pair));
    }

    function test_PairCannotBeInitializedTwice() public {
        MockV2Pair secondPair = new MockV2Pair(factory, address(token), address(weth));

        vm.expectRevert(KOANT.PairAlreadyInitialized.selector);
        vm.prank(treasury);
        token.initializePair(address(secondPair));
    }

    function test_InvalidPairIsRejected() public {
        KOANT freshToken =
            new KOANT(treasury, founder1, founder2, genesisSafe, teamVault, address(router), 40_469_000 ether);

        MockV2Pair invalidPair = new MockV2Pair(makeAddr("wrongFactory"), address(freshToken), address(weth));

        vm.expectRevert(KOANT.InvalidPair.selector);
        vm.prank(treasury);
        freshToken.initializePair(address(invalidPair));
    }

    function test_CannotEnableTradingBeforePairInitialization() public {
        KOANT freshToken =
            new KOANT(treasury, founder1, founder2, genesisSafe, teamVault, address(router), 40_469_000 ether);

        vm.expectRevert(KOANT.PairNotInitialized.selector);
        vm.prank(treasury);
        freshToken.enableTrading();
    }

    function test_NonTreasuryCannotEnableTrading() public {
        vm.expectRevert(KOANT.NotTreasury.selector);
        vm.prank(alice);
        token.enableTrading();
    }

    function test_PublicBuyRevertsBeforeTrading() public {
        vm.expectRevert(KOANT.TradingNotEnabled.selector);
        pair.sendToken(address(token), alice, 100 ether);
    }

    function test_GenesisLiquidityTransferAllowedBeforeTrading() public view {
        assertEq(token.balanceOf(address(pair)), 10_000_000_000 ether);
        assertEq(token.buyCount(), 0);
        assertFalse(token.tradingEnabled());
    }

    function test_TreasuryEnablesOnce() public {
        vm.prank(treasury);
        token.enableTrading();

        assertTrue(token.tradingEnabled());

        vm.expectRevert(KOANT.TradingAlreadyEnabled.selector);
        vm.prank(treasury);
        token.enableTrading();
    }

    function test_PublicBuyWorksAfterTradingEnabled() public {
        vm.prank(treasury);
        token.enableTrading();

        pair.sendToken(address(token), alice, 100 ether);

        assertEq(token.buyCount(), 1);
        assertEq(token.balanceOf(alice), 99 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
    }
}
