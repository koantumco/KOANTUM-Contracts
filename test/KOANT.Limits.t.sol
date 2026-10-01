// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {KOANT} from "../src/KOANT.sol";
import {MockV2Router} from "./mocks/MockV2Router.sol";
import {MockV2Pair} from "./mocks/MockV2Pair.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract KOANTLimitsTest is Test {
    MockERC20 wethToken;
    address weth;

    address treasury = makeAddr("treasury");
    address founder1 = makeAddr("founder1");
    address founder2 = makeAddr("founder2");
    address genesisSafe = makeAddr("genesisSafe");
    address teamVault = makeAddr("teamVault");
    address factory = makeAddr("factory");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

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

    function test_BuyExactlyMaxSucceeds() public {
        uint256 maxBuy = token.MAX_BUY();
        uint256 fee = (maxBuy * token.INITIAL_BUY_TAX_BPS()) / token.BPS_DENOMINATOR();

        pair.sendToken(address(token), alice, maxBuy);

        assertEq(token.buyCount(), 1);
        assertEq(token.balanceOf(alice), maxBuy - fee);
        assertEq(token.balanceOf(address(token)), fee);
    }

    function test_BuyOverMaxReverts() public {
        uint256 maxBuy = token.MAX_BUY();

        vm.expectRevert(abi.encodeWithSelector(KOANT.MaxBuyExceeded.selector, maxBuy + 1, maxBuy));

        pair.sendToken(address(token), alice, maxBuy + 1);
    }

    function test_MaxWalletExactTransferSucceeds() public {
        uint256 maxWallet = token.MAX_WALLET();

        vm.prank(genesisSafe);
        token.transfer(alice, maxWallet);

        assertEq(token.balanceOf(alice), maxWallet);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.buyCount(), 0);
    }

    function test_MaxWalletPlusOneTransferReverts() public {
        uint256 maxWallet = token.MAX_WALLET();

        vm.prank(genesisSafe);
        token.transfer(alice, maxWallet);

        vm.startPrank(genesisSafe);

        vm.expectRevert(abi.encodeWithSelector(KOANT.MaxWalletExceeded.selector, maxWallet + 1, maxWallet));

        token.transfer(alice, 1);

        vm.stopPrank();
    }

    function test_FounderCannotExceedMaxWalletByBuying() public {
        uint256 maxWallet = token.MAX_WALLET();
        uint256 founderBalance = token.balanceOf(founder1);
        uint256 room = maxWallet - founderBalance;

        // During the first 69 buys the user receives 99% of gross amount.
        // Choose enough gross KOANT so the founder's final balance exceeds
        // MAX_WALLET.
        uint256 grossNeededToExceed =
            (room * token.BPS_DENOMINATOR()) / (token.BPS_DENOMINATOR() - token.INITIAL_BUY_TAX_BPS()) + 2;

        uint256 expectedFee = (grossNeededToExceed * token.INITIAL_BUY_TAX_BPS()) / token.BPS_DENOMINATOR();

        uint256 expectedNetAmount = grossNeededToExceed - expectedFee;

        uint256 expectedFinalBalance = founderBalance + expectedNetAmount;

        vm.expectRevert(abi.encodeWithSelector(KOANT.MaxWalletExceeded.selector, expectedFinalBalance, maxWallet));

        pair.sendToken(address(token), founder1, grossNeededToExceed);
    }

    function test_WalletToWalletTransferHasNoTax() public {
        uint256 amount = 100 ether;

        uint256 founderBefore = token.balanceOf(founder1);
        uint256 contractBefore = token.balanceOf(address(token));

        vm.prank(founder1);
        token.transfer(bob, amount);

        assertEq(token.balanceOf(founder1), founderBefore - amount);

        assertEq(token.balanceOf(bob), amount);

        // Normal wallet-to-wallet transfer must not create fees.
        assertEq(token.balanceOf(address(token)), contractBefore);

        // It is also not a Buy.
        assertEq(token.buyCount(), 0);
    }

    function test_WalletToWalletStillRespectsMaxWallet() public {
        uint256 maxWallet = token.MAX_WALLET();

        vm.prank(genesisSafe);
        token.transfer(alice, maxWallet);

        vm.startPrank(founder1);

        vm.expectRevert(abi.encodeWithSelector(KOANT.MaxWalletExceeded.selector, maxWallet + 1, maxWallet));

        token.transfer(alice, 1);

        vm.stopPrank();
    }
}
