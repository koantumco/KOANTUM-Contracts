// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {KOANT} from "../src/KOANT.sol";
import {MockV2Router} from "./mocks/MockV2Router.sol";
import {MockV2Pair} from "./mocks/MockV2Pair.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract KOANTAdversarialTest is Test {
    MockERC20 wethToken;
    address weth;

    address treasury = makeAddr("treasury");
    address founder1 = makeAddr("founder1");
    address founder2 = makeAddr("founder2");
    address genesisSafe = makeAddr("genesisSafe");
    address teamVault = makeAddr("teamVault");
    address factory = makeAddr("factory");
    address attacker = makeAddr("attacker");
    address otherWallet = makeAddr("otherWallet");
    address seller = makeAddr("seller");

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

        // Give the mock Pair a WETH side as well, then record
        // both balances as the pre-trading V2 reserves.
        wethToken.mint(address(pair), 10 ether);
        pair.sync();

        vm.prank(treasury);
        token.enableTrading();

        vm.deal(address(router), 10 ether);
        router.setEthOutPerSwap(0.01 ether);

        assertEq(token.buyCount(), 0);
    }

    function test_SkimLikeOutflowDoesNotCountAsBuy() public {
        // Give attacker exactly 1 wei of KOANT.
        vm.prank(founder1);
        token.transfer(attacker, 1);

        assertEq(token.balanceOf(attacker), 1);
        assertEq(token.buyCount(), 0);

        // Donate 1 wei above the recorded KOANT reserve.
        // The 50% sell tax rounds down to zero.
        vm.prank(attacker);
        token.transfer(address(pair), 1);

        assertEq(token.balanceOf(address(token)), 0);

        // Raw Pair outflow with no WETH swap input.
        //
        // At this moment KOANT balance is above the recorded
        // KOANT reserve, so this must NOT qualify as realBuy.
        pair.skimToken(address(token), attacker, 1);

        assertEq(token.balanceOf(attacker), 1);
        assertEq(token.balanceOf(address(token)), 0);

        // Critical regression assertion.
        assertEq(token.buyCount(), 0);

        // Tax schedules must remain untouched.
        assertEq(token.activeBuyTaxBps(), token.INITIAL_BUY_TAX_BPS());

        assertEq(token.activeSellTaxBps(), token.INITIAL_SELL_TAX_BPS());
    }

    function test_OneWeiSkimCycleCannotAdvanceBuyCountTo404() public {
        vm.prank(founder1);
        token.transfer(attacker, 1);

        assertEq(token.buyCount(), 0);

        assertEq(token.activeSellTaxBps(), token.INITIAL_SELL_TAX_BPS());

        // Repeat the previously vulnerable sequence 404 times:
        //
        // attacker -> Pair : donate 1 wei
        // Pair -> attacker : skim-like raw outflow
        //
        // None of these is a WETH -> KOANT swap.
        for (uint256 i = 0; i < 404; ++i) {
            vm.prank(attacker);
            token.transfer(address(pair), 1);

            pair.skimToken(address(token), attacker, 1);
        }

        assertEq(token.balanceOf(attacker), 1);
        assertEq(token.balanceOf(address(token)), 0);

        // The former counter-acceleration path must be closed.
        assertEq(token.buyCount(), 0);

        assertEq(token.activeBuyTaxBps(), token.INITIAL_BUY_TAX_BPS());

        assertEq(token.activeSellTaxBps(), token.INITIAL_SELL_TAX_BPS());
    }

    function test_RealBuyStillAdvancesBuyCounter() public {
        uint256 grossAmount = 100 ether;

        uint256 expectedFee = (grossAmount * token.INITIAL_BUY_TAX_BPS()) / token.BPS_DENOMINATOR();

        // MockV2Pair.sendToken() simulates the classification-relevant
        // V2 ordering:
        //
        // reserves recorded
        // -> WETH input arrives
        // -> KOANT leaves Pair
        // -> reserves update
        pair.sendToken(address(token), attacker, grossAmount);

        assertEq(token.buyCount(), 1);

        assertEq(token.balanceOf(attacker), grossAmount - expectedFee);

        assertEq(token.balanceOf(address(token)), expectedFee);
    }

    function test_RevertedOverMaxBuyDoesNotAdvanceCounter() public {
        uint256 countBefore = token.buyCount();

        uint256 pairBalanceBefore = token.balanceOf(address(pair));

        uint256 contractFeeBefore = token.balanceOf(address(token));

        uint256 tooLarge = token.MAX_BUY() + 1;

        vm.expectRevert(abi.encodeWithSelector(KOANT.MaxBuyExceeded.selector, tooLarge, token.MAX_BUY()));

        pair.sendToken(address(token), attacker, tooLarge);

        assertEq(token.buyCount(), countBefore);

        assertEq(token.balanceOf(address(pair)), pairBalanceBefore);

        assertEq(token.balanceOf(address(token)), contractFeeBefore);
    }

    function test_WalletTransferAndSellDoNotAdvanceBuyCounter() public {
        vm.prank(founder1);
        token.transfer(attacker, 1_000_000 ether);

        assertEq(token.buyCount(), 0);

        vm.prank(attacker);
        token.transfer(otherWallet, 100_000 ether);

        assertEq(token.buyCount(), 0);

        vm.prank(attacker);
        token.transfer(address(pair), 100_000 ether);

        // Sell may create fee, but must not increment buyCount.
        assertEq(token.buyCount(), 0);
    }

    function test_RepeatedSwapBackIsCappedAtThresholdPerTrigger() public {
        vm.prank(founder1);
        token.transfer(seller, 200_000_000 ether);

        // First large sell:
        // pre-existing fee is zero, so no swapBack yet.
        // 50% sell tax creates 45M KOANT fee.
        vm.prank(seller);
        token.transfer(address(pair), 90_000_000 ether);

        assertEq(token.balanceOf(address(token)), 45_000_000 ether);

        assertEq(token.balanceOf(address(router)), 0);

        // Next sell triggers exactly one threshold-sized swap.
        vm.prank(seller);
        token.transfer(address(pair), 100_000 ether);

        assertEq(token.balanceOf(address(router)), TEST_THRESHOLD);

        assertEq(treasury.balance, 0.01 ether);

        // Build fee balance above threshold again.
        vm.prank(seller);
        token.transfer(address(pair), 90_000_000 ether);

        // No second swap yet because the balance was checked
        // before processing this sell.
        assertEq(token.balanceOf(address(router)), TEST_THRESHOLD);

        // Next sell triggers the second capped swap.
        vm.prank(seller);
        token.transfer(address(pair), 100_000 ether);

        assertEq(token.balanceOf(address(router)), TEST_THRESHOLD * 2);

        assertEq(treasury.balance, 0.02 ether);
    }

    function test_DirectEthFromNonRouterIsRejected() public {
        vm.deal(attacker, 1 ether);

        uint256 tokenEthBefore = address(token).balance;

        vm.prank(attacker);
        (bool success,) = address(token).call{value: 1 wei}("");

        assertFalse(success);

        assertEq(address(token).balance, tokenEthBefore);
    }
}
