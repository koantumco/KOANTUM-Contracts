// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {KOANT} from "../src/KOANT.sol";

interface IBaseV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IBaseV2Pair {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function skim(address to) external;
}

interface IBaseForkRouterValidation {
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}

contract KOANTBaseForkPairBehaviorTest is Test {
    string constant BASE_RPC_URL = "https://mainnet.base.org";

    address constant UNISWAP_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address constant UNISWAP_V2_ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    uint256 constant TEST_THRESHOLD = 40_469_000 ether;

    address treasury = makeAddr("treasury");
    address founder1 = makeAddr("founder1");
    address founder2 = makeAddr("founder2");
    address genesisSafe = makeAddr("genesisSafe");
    address teamVault = makeAddr("teamVault");
    address attacker = makeAddr("attacker");

    KOANT token;
    IBaseV2Pair pair;

    function setUp() public {
        vm.createSelectFork(BASE_RPC_URL);

        token = new KOANT(treasury, founder1, founder2, genesisSafe, teamVault, UNISWAP_V2_ROUTER, TEST_THRESHOLD);

        address pairAddress = IBaseV2Factory(UNISWAP_V2_FACTORY).createPair(address(token), WETH);

        pair = IBaseV2Pair(pairAddress);

        assertEq(pair.factory(), UNISWAP_V2_FACTORY);

        address token0 = pair.token0();
        address token1 = pair.token1();
        bool validTokens = (token0 == address(token) && token1 == WETH) || (token1 == address(token) && token0 == WETH);
        assertTrue(validTokens);

        vm.prank(treasury);
        token.initializePair(pairAddress);

        vm.prank(treasury);
        token.enableTrading();

        assertEq(token.buyCount(), 0);
    }

    function test_RealBasePairSkimOneWeiDoesNotCountAsBuy() public {
        // Give the test wallet exactly 1 wei of KOANT.
        vm.prank(founder1);
        token.transfer(attacker, 1);

        assertEq(token.balanceOf(attacker), 1);
        assertEq(token.buyCount(), 0);

        // Donate 1 wei to the real Uniswap V2 Pair.
        // The 50% sell tax rounds down to zero at this size.
        vm.prank(attacker);
        token.transfer(address(pair), 1);

        assertEq(token.balanceOf(attacker), 0);
        assertEq(token.buyCount(), 0);

        // Real Pair skim() returns the excess token balance.
        // KOANT sees Pair -> ordinary wallet as a buy.
        pair.skim(attacker);

        assertEq(token.balanceOf(attacker), 1);
        assertEq(token.balanceOf(address(pair)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.buyCount(), 0);
    }

    function test_RealBasePairSkimCycleDoesNotAdvanceBuyCount() public {
        vm.prank(founder1);
        token.transfer(attacker, 1);

        assertEq(token.buyCount(), 0);
        assertEq(token.activeBuyTaxBps(), token.INITIAL_BUY_TAX_BPS());
        assertEq(token.activeSellTaxBps(), token.INITIAL_SELL_TAX_BPS());

        for (uint256 i = 0; i < 404; ++i) {
            vm.prank(attacker);
            token.transfer(address(pair), 1);

            pair.skim(attacker);
        }

        assertEq(token.balanceOf(attacker), 1);
        assertEq(token.balanceOf(address(pair)), 0);
        assertEq(token.balanceOf(address(token)), 0);

        assertEq(token.buyCount(), 0);
        assertEq(token.activeBuyTaxBps(), token.INITIAL_BUY_TAX_BPS());
        assertEq(token.activeSellTaxBps(), token.INITIAL_SELL_TAX_BPS());
    }

    function _baseValidationRouter() internal pure returns (IBaseForkRouterValidation) {
        return IBaseForkRouterValidation(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);
    }

    function _seedBaseValidationLiquidity() internal {
        uint256 koantLiquidity = 1_000_000_000 ether;
        uint256 ethLiquidity = 10 ether;

        IBaseForkRouterValidation realRouter = _baseValidationRouter();

        vm.deal(genesisSafe, 20 ether);

        vm.startPrank(genesisSafe);

        token.approve(address(realRouter), koantLiquidity);

        realRouter.addLiquidityETH{value: ethLiquidity}(
            address(token), koantLiquidity, 0, 0, genesisSafe, block.timestamp
        );

        vm.stopPrank();

        // Adding foundational-style liquidity must never
        // advance the genuine-buy counter.
        assertEq(token.buyCount(), 0);
    }

    function _executeRealBaseBuy(address buyer, uint256 ethAmount) internal {
        address[] memory path = new address[](2);

        path[0] = 0x4200000000000000000000000000000000000006;
        path[1] = address(token);

        vm.prank(buyer);

        _baseValidationRouter().swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0, path, buyer, block.timestamp
        );
    }

    function test_RealBaseWethToKoantSwapCountsExactlyOneBuy() public {
        _seedBaseValidationLiquidity();

        address buyer = makeAddr("realBaseBuyer");
        vm.deal(buyer, 1 ether);

        uint256 countBefore = token.buyCount();
        uint256 feeBefore = token.balanceOf(address(token));

        _executeRealBaseBuy(buyer, 0.001 ether);

        assertEq(token.buyCount(), countBefore + 1);

        assertGt(token.balanceOf(buyer), 0);

        // Buy #1 must still charge the configured 1% fee.
        assertGt(token.balanceOf(address(token)), feeBefore);

        assertEq(token.activeBuyTaxBps(), token.INITIAL_BUY_TAX_BPS());
    }

    function test_RealBaseSwapsPreserve69_70_404Boundaries() public {
        _seedBaseValidationLiquidity();

        address buyer = makeAddr("realBaseBoundaryBuyer");

        vm.deal(buyer, 1 ether);

        uint256 buySize = 0.0001 ether;

        // Complete Buy #1 through Buy #68.
        for (uint256 i = 0; i < 68; ++i) {
            _executeRealBaseBuy(buyer, buySize);
        }

        assertEq(token.buyCount(), 68);

        uint256 feeBefore69 = token.balanceOf(address(token));

        // Buy #69: still taxed.
        _executeRealBaseBuy(buyer, buySize);

        assertEq(token.buyCount(), 69);

        uint256 feeAfter69 = token.balanceOf(address(token));

        assertGt(feeAfter69, feeBefore69);

        // Buy #70: no new buy tax.
        _executeRealBaseBuy(buyer, buySize);

        assertEq(token.buyCount(), 70);

        assertEq(token.balanceOf(address(token)), feeAfter69);

        assertEq(token.activeBuyTaxBps(), 0);

        // Complete Buy #71 through Buy #404.
        for (uint256 i = 70; i < 404; ++i) {
            _executeRealBaseBuy(buyer, buySize);
        }

        assertEq(token.buyCount(), 404);

        assertEq(token.activeBuyTaxBps(), 0);

        assertEq(token.activeSellTaxBps(), 0);

        // One more genuine buy proves the tax end-state
        // remains zero after the 404 boundary.
        _executeRealBaseBuy(buyer, buySize);

        assertEq(token.buyCount(), 405);

        assertEq(token.activeBuyTaxBps(), 0);

        assertEq(token.activeSellTaxBps(), 0);
    }

    function test_RealBaseOneWeiKoantDustMustNotSuppressRealBuy() public {
        _seedBaseValidationLiquidity();

        address dustSender = makeAddr("baseDustSender");

        address buyer = makeAddr("baseDustBuyer");

        vm.deal(buyer, 1 ether);

        // Give the dust sender exactly 1 wei KOANT.
        vm.prank(founder1);
        token.transfer(dustSender, 1);

        // Donate that 1 wei directly to the Pair.
        // At this amount, the 50% sell fee rounds to zero.
        address realPair = token.pair();

        vm.prank(dustSender);
        token.transfer(realPair, 1);

        assertEq(token.buyCount(), 0);

        // A genuine WETH -> KOANT swap must still count
        // even if the Pair has received unsolicited dust.
        _executeRealBaseBuy(buyer, 0.001 ether);

        assertEq(token.buyCount(), 1);
    }
}
