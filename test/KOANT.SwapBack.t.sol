// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {KOANT} from "../src/KOANT.sol";
import {MockV2Router} from "./mocks/MockV2Router.sol";
import {MockV2Pair} from "./mocks/MockV2Pair.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract KOANTSwapBackTest is Test {
    MockERC20 wethToken;
    address weth;

    address treasury = makeAddr("treasury");
    address founder1 = makeAddr("founder1");
    address founder2 = makeAddr("founder2");
    address genesisSafe = makeAddr("genesisSafe");
    address teamVault = makeAddr("teamVault");
    address factory = makeAddr("factory");
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");

    uint256 constant TEST_THRESHOLD = 40_469_000 ether;

    KOANT token;
    MockV2Router router;
    MockV2Pair pair;

    function setUp() public {
        wethToken = new MockERC20("Wrapped Ether", "WETH");
        weth = address(wethToken);
        router = new MockV2Router(factory, address(weth));

        token = new KOANT(treasury, founder1, founder2, genesisSafe, teamVault, address(router), TEST_THRESHOLD);

        pair = new MockV2Pair(factory, address(weth), address(token));

        vm.prank(treasury);
        token.initializePair(address(pair));

        vm.prank(genesisSafe);
        token.transfer(address(pair), 20_000_000_000 ether);

        vm.prank(treasury);
        token.enableTrading();

        // Real Buy #1:
        // seller receives 99,000,000 KOANT
        // KOANT contract receives 1,000,000 KOANT fee.
        pair.sendToken(address(token), seller, 100_000_000 ether);

        // Fund mock router so it can simulate ETH output.
        vm.deal(address(router), 10 ether);
        router.setEthOutPerSwap(0.01 ether);
    }

    function test_ThresholdIsConstructorConfigured() public view {
        assertEq(token.swapThreshold(), TEST_THRESHOLD);
    }

    function test_ThresholdCannotBeChangedBySetter() public {
        uint256 beforeThreshold = token.swapThreshold();

        (bool ok,) = address(token).call(abi.encodeWithSignature("setSwapThreshold(uint256)", 1 ether));

        assertFalse(ok);

        assertEq(token.swapThreshold(), beforeThreshold);
    }

    function test_NoSwapBackBelowThreshold() public {
        // Pre-existing contract fee = 1,000,000 KOANT.

        // This sell adds another 10,000,000 KOANT fee.
        // The pre-existing balance was still below threshold,
        // so this sell itself must not trigger swapBack.
        vm.prank(seller);
        token.transfer(address(pair), 20_000_000 ether);

        assertEq(treasury.balance, 0);
        assertEq(token.balanceOf(address(router)), 0);

        // Contract now holds 11,000,000 KOANT fee.
        assertEq(token.balanceOf(address(token)), 11_000_000 ether);

        // Another sell still sees a pre-existing balance
        // below threshold and therefore must not swap.
        vm.prank(seller);
        token.transfer(address(pair), 1_000_000 ether);

        assertEq(treasury.balance, 0);
        assertEq(token.balanceOf(address(router)), 0);

        // Adds another 500,000 KOANT sell fee.
        assertEq(token.balanceOf(address(token)), 11_500_000 ether);
    }

    function test_BuyDoesNotTriggerSwapBackEvenAboveThreshold() public {
        // Initial contract fee from Buy #1 = 1,000,000.

        // This sell adds 45,000,000 fee.
        // Pre-existing fee before the sell is below threshold,
        // so no swap occurs during this sell.
        vm.prank(seller);
        token.transfer(address(pair), 90_000_000 ether);

        assertEq(token.balanceOf(address(token)), 46_000_000 ether);

        assertEq(treasury.balance, 0);
        assertEq(token.balanceOf(address(router)), 0);

        // Contract fee is now above threshold,
        // but a BUY must not trigger swapBack.
        pair.sendToken(address(token), buyer, 1_000_000 ether);

        assertEq(treasury.balance, 0);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function test_SellTriggersExactlyThresholdSwap() public {
        // Build fee balance above threshold.
        vm.prank(seller);
        token.transfer(address(pair), 90_000_000 ether);

        uint256 feeBefore = token.balanceOf(address(token));

        assertEq(feeBefore, 46_000_000 ether);

        uint256 treasuryBefore = treasury.balance;

        // This later sell sees the pre-existing
        // 46M KOANT and triggers a threshold-sized swap.
        vm.prank(seller);
        token.transfer(address(pair), 100_000 ether);

        assertEq(token.balanceOf(address(router)), TEST_THRESHOLD);

        assertEq(treasury.balance - treasuryBefore, 0.01 ether);

        // Current sell still has 50% tax:
        // 100,000 / 2 = 50,000 KOANT.
        uint256 expectedRemainingFee = feeBefore - TEST_THRESHOLD + 50_000 ether;

        assertEq(token.balanceOf(address(token)), expectedRemainingFee);
    }

    function test_SwapBackEthOnlyGoesToTreasury() public {
        vm.prank(seller);
        token.transfer(address(pair), 90_000_000 ether);

        uint256 sellerEthBefore = seller.balance;

        uint256 tokenEthBefore = address(token).balance;

        uint256 treasuryBefore = treasury.balance;

        vm.prank(seller);
        token.transfer(address(pair), 100_000 ether);

        assertEq(treasury.balance - treasuryBefore, 0.01 ether);

        assertEq(seller.balance, sellerEthBefore);

        assertEq(address(token).balance, tokenEthBefore);
    }

    function test_SwapBackTransferDoesNotRecurseOrTaxItself() public {
        vm.prank(seller);
        token.transfer(address(pair), 90_000_000 ether);

        uint256 feeBefore = token.balanceOf(address(token));

        vm.prank(seller);
        token.transfer(address(pair), 100_000 ether);

        // Router must receive the FULL threshold.
        // If internal swap transfer were taxed or recursively
        // processed, this exact equality would fail.
        assertEq(token.balanceOf(address(router)), TEST_THRESHOLD);

        uint256 expectedRemainingFee = feeBefore - TEST_THRESHOLD + 50_000 ether;

        assertEq(token.balanceOf(address(token)), expectedRemainingFee);
    }

    function test_AfterBuy404ResidualBelowThresholdIsSwept() public {
        // setUp already completed Buy #1.
        assertEq(token.buyCount(), 1);

        // Complete another 403 tiny buys.
        // Buy #2 through #69 still generate 1% tax.
        // Buy #70 through #404 generate zero buy tax.
        for (uint256 i = 0; i < 403; ++i) {
            pair.sendToken(address(token), buyer, 1 ether);
        }

        assertEq(token.buyCount(), 404);
        assertEq(token.activeBuyTaxBps(), 0);
        assertEq(token.activeSellTaxBps(), 0);

        uint256 residualBefore = token.balanceOf(address(token));

        assertGt(residualBefore, 0);
        assertLt(residualBefore, TEST_THRESHOLD);

        uint256 treasuryBefore = treasury.balance;

        // Taxes have ended.
        // A sell must sweep even a residual below threshold.
        vm.prank(seller);
        token.transfer(address(pair), 1 ether);

        assertEq(token.balanceOf(address(router)), residualBefore);

        assertEq(token.balanceOf(address(token)), 0);

        assertEq(treasury.balance - treasuryBefore, 0.01 ether);
    }

    function test_SellAfterBuy404CreatesNoNewFee() public {
        // Move from Buy #1 to Buy #404.
        for (uint256 i = 0; i < 403; ++i) {
            pair.sendToken(address(token), buyer, 1 ether);
        }

        assertEq(token.buyCount(), 404);
        assertEq(token.activeSellTaxBps(), 0);

        // First sell after tax end also clears old residual.
        vm.prank(seller);
        token.transfer(address(pair), 1 ether);

        assertEq(token.balanceOf(address(token)), 0);

        uint256 pairBefore = token.balanceOf(address(pair));

        // Second sell: no old residual and no new sell tax.
        vm.prank(seller);
        token.transfer(address(pair), 100 ether);

        assertEq(token.balanceOf(address(token)), 0);

        assertEq(token.balanceOf(address(pair)), pairBefore + 100 ether);
    }
}
