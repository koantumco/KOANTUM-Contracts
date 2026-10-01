// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {KOANT} from "../src/KOANT.sol";
import {MockV2Router} from "./mocks/MockV2Router.sol";
import {MockV2Pair} from "./mocks/MockV2Pair.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract KOANTFuzzTest is Test {
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

    function testFuzz_BuyNeverLeavesOrdinaryWalletAboveMax(uint96 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1 ether, token.MAX_BUY());
        address user = makeAddr("fuzzUser");
        pair.sendToken(address(token), user, amount);
        assertLe(token.balanceOf(user), token.MAX_WALLET());
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }
}
