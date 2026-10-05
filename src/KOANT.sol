// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02Minimal} from "./interfaces/IUniswapV2Router02Minimal.sol";
import {IUniswapV2PairMinimal} from "./interfaces/IUniswapV2PairMinimal.sol";

/// @notice KOANTUM fixed-supply ERC20 for Base / Uniswap V2.
contract KOANT is ERC20 {
    error ZeroAddress();
    error DuplicateRoleAddress();
    error NotTreasury();
    error PairAlreadyInitialized();
    error PairNotInitialized();
    error InvalidPair();
    error TradingAlreadyEnabled();
    error TradingNotEnabled();
    error MaxBuyExceeded(uint256 amount, uint256 maxBuy);
    error MaxWalletExceeded(uint256 resultingBalance, uint256 maxWallet);
    error InvalidSwapThreshold(uint256 threshold);
    error EtherSenderNotRouter();
    error InvalidRouter();
    error TreasuryTransferFailed();

    uint256 public constant TOTAL_SUPPLY = 404_690_000_000 ether;
    uint256 public constant FOUNDER_ALLOCATION = 6_070_350_000 ether; // 1.5%
    uint256 public constant TEAM_VAULT_ALLOCATION = 15_782_910_000 ether; // 3.9%
    uint256 public constant GENESIS_SAFE_ALLOCATION = 376_766_390_000 ether; // 93.1%
    uint256 public constant GENESIS_LP_ALLOCATION = 348_842_780_000 ether; // 86.2%
    uint256 public constant COMMUNITY_RESERVE = 27_923_610_000 ether; // 6.9%

    uint256 public constant MAX_BUY = 6_976_855_600 ether;
    uint256 public constant MAX_WALLET = 6_976_855_600 ether;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant INITIAL_BUY_TAX_BPS = 100; // 1%
    uint256 public constant INITIAL_SELL_TAX_BPS = 5_000; // 50%
    uint256 public constant BUY_TAX_END_COUNT = 69;
    uint256 public constant SELL_TAX_END_COUNT = 404;

    uint256 public constant MIN_SWAP_THRESHOLD = 40_469_000 ether; // 0.01%
    uint256 public constant MAX_SWAP_THRESHOLD = 2_023_450_000 ether; // 0.5%

    address public immutable treasury;
    address public immutable founder1;
    address public immutable founder2;
    address public immutable genesisSafe;
    address public immutable teamVault;

    IUniswapV2Router02Minimal public immutable router;
    address public immutable factory;
    address public immutable WETH;
    uint256 public immutable swapThreshold;

    address public pair;
    bool public pairInitialized;
    bool public tradingEnabled;
    bool private inSwap;
    uint256 public buyCount;

    event PairInitialized(address indexed pair);
    event TradingEnabled(uint256 timestamp);
    event BuyTaxEnded(uint256 buyCount);
    event SellTaxEnded(uint256 buyCount);
    event SwapBackExecuted(uint256 tokenAmount, uint256 ethAmount);

    modifier onlyTreasury() {
        if (msg.sender != treasury) revert NotTreasury();
        _;
    }

    constructor(
        address treasury_,
        address founder1_,
        address founder2_,
        address genesisSafe_,
        address teamVault_,
        address router_,
        uint256 swapThreshold_
    ) ERC20("KOANTUM", "KOANT") {
        if (
            treasury_ == address(0) || founder1_ == address(0) || founder2_ == address(0) || genesisSafe_ == address(0)
                || teamVault_ == address(0) || router_ == address(0)
        ) revert ZeroAddress();

        if (
            treasury_ == founder1_ || treasury_ == founder2_ || treasury_ == genesisSafe_ || treasury_ == teamVault_
                || founder1_ == founder2_ || founder1_ == genesisSafe_ || founder1_ == teamVault_
                || founder2_ == genesisSafe_ || founder2_ == teamVault_ || genesisSafe_ == teamVault_
        ) revert DuplicateRoleAddress();

        if (swapThreshold_ < MIN_SWAP_THRESHOLD || swapThreshold_ > MAX_SWAP_THRESHOLD) {
            revert InvalidSwapThreshold(swapThreshold_);
        }

        treasury = treasury_;
        founder1 = founder1_;
        founder2 = founder2_;
        genesisSafe = genesisSafe_;
        teamVault = teamVault_;
        router = IUniswapV2Router02Minimal(router_);
        address factory_ = IUniswapV2Router02Minimal(router_).factory();
        address weth_ = IUniswapV2Router02Minimal(router_).WETH();
        if (factory_ == address(0) || weth_ == address(0)) revert InvalidRouter();
        factory = factory_;
        WETH = weth_;
        swapThreshold = swapThreshold_;

        _mint(founder1_, FOUNDER_ALLOCATION);
        _mint(founder2_, FOUNDER_ALLOCATION);
        _mint(teamVault_, TEAM_VAULT_ALLOCATION);
        _mint(genesisSafe_, GENESIS_SAFE_ALLOCATION);

        assert(totalSupply() == TOTAL_SUPPLY);
        assert(balanceOf(treasury_) == 0);
    }

    receive() external payable {
        if (msg.sender != address(router)) revert EtherSenderNotRouter();
    }

    function initializePair(address pair_) external onlyTreasury {
        if (pairInitialized) revert PairAlreadyInitialized();
        if (pair_ == address(0) || pair_.code.length == 0) {
            revert InvalidPair();
        }

        IUniswapV2PairMinimal p = IUniswapV2PairMinimal(pair_);

        if (p.factory() != factory) revert InvalidPair();

        // Security invariant:
        // WETH must be token0 and KOANT must be token1.
        //
        // Uniswap V2 skim() and burn() transfer token0
        // before token1. This ordering lets genuine
        // WETH -> KOANT swaps be distinguished from
        // skim / liquidity-removal outflows.
        if (p.token0() != WETH || p.token1() != address(this)) {
            revert InvalidPair();
        }

        pair = pair_;
        pairInitialized = true;

        emit PairInitialized(pair_);
    }

    function enableTrading() external onlyTreasury {
        if (!pairInitialized) revert PairNotInitialized();
        if (tradingEnabled) revert TradingAlreadyEnabled();
        tradingEnabled = true;
        emit TradingEnabled(block.timestamp);
    }

    function activeBuyTaxBps() public view returns (uint256) {
        return buyCount < BUY_TAX_END_COUNT ? INITIAL_BUY_TAX_BPS : 0;
    }

    function activeSellTaxBps() public view returns (uint256) {
        return buyCount < SELL_TAX_END_COUNT ? INITIAL_SELL_TAX_BPS : 0;
    }

    function _isSystem(address account) internal view returns (bool) {
        return account == treasury || account == genesisSafe || account == teamVault || account == address(this)
            || (pairInitialized && account == pair);
    }

    function _isCountedV2Buy() internal view returns (bool) {
        // initializePair guarantees:
        // token0 = WETH
        // token1 = KOANT
        //
        // In a normal WETH -> KOANT V2 swap, WETH input
        // reaches the Pair before KOANT is transferred out.
        //
        // Therefore WETH balance is above its recorded
        // reserve at the exact moment KOANT leaves the Pair.
        //
        // KOANT dust is deliberately ignored here so an
        // unsolicited token donation cannot suppress a
        // genuine buy.
        (uint112 wethReserve,,) = IUniswapV2PairMinimal(pair).getReserves();

        return IERC20(WETH).balanceOf(pair) > uint256(wethReserve);
    }

    function _update(address from, address to, uint256 amount) internal override {
        // Mint/burn paths bypass trading rules. Supply is only minted in constructor.
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        // Internal swapBack transfer must not recurse into fee/limit logic.
        if (inSwap) {
            super._update(from, to, amount);
            return;
        }

        bool isBuy = pairInitialized && from == pair && to != address(this);
        bool isSell = pairInitialized && to == pair && from != address(this);
        bool systemRecipient = _isSystem(to);
        bool systemSender = _isSystem(from);
        bool teamVaultRelease = from == teamVault;
        bool realBuy = isBuy && !systemRecipient && _isCountedV2Buy();
        bool publicSell = isSell && !systemSender;

        // Before public trading opens, the only Pair-facing token movement allowed is
        // Genesis Safe -> Pair for the approved initial liquidity operation.
        if (!tradingEnabled && (isBuy || isSell)) {
            bool approvedGenesisLiquidityTransfer = isSell && from == genesisSafe;
            if (!approvedGenesisLiquidityTransfer) revert TradingNotEnabled();
        }

        // Swap pre-existing fee balance before processing the user's sell.
        if (publicSell) {
            _maybeSwapBack();
        }

        if (realBuy && amount > MAX_BUY) revert MaxBuyExceeded(amount, MAX_BUY);

        uint256 taxBps = 0;
        if (realBuy) {
            taxBps = activeBuyTaxBps();
        } else if (publicSell) {
            taxBps = activeSellTaxBps();
        }

        uint256 feeAmount = (amount * taxBps) / BPS_DENOMINATOR;
        uint256 netAmount = amount - feeAmount;

        // Max wallet applies to ordinary recipients. Pair/system destinations are exempt by role.
        //
        // The immutable TeamVault is a deliberate one-time allocation source whose
        // 3.9% balance is larger than MAX_WALLET. Its release to the fixed vault
        // beneficiary must therefore bypass only this recipient-balance check.
        // This does not make the beneficiary a system address: all other inbound
        // transfers and buys remain subject to the normal max-wallet rules.
        if (!systemRecipient && !teamVaultRelease) {
            uint256 resultingBalance = balanceOf(to) + netAmount;
            if (resultingBalance > MAX_WALLET) revert MaxWalletExceeded(resultingBalance, MAX_WALLET);
        }

        if (feeAmount != 0) {
            super._update(from, address(this), feeAmount);
        }
        super._update(from, to, netAmount);

        if (realBuy) {
            unchecked {
                ++buyCount;
            }
            if (buyCount == BUY_TAX_END_COUNT) emit BuyTaxEnded(buyCount);
            if (buyCount == SELL_TAX_END_COUNT) emit SellTaxEnded(buyCount);
        }
    }

    function _maybeSwapBack() internal {
        uint256 feeBalance = balanceOf(address(this));
        if (feeBalance == 0) return;

        bool taxesEnded = buyCount >= SELL_TAX_END_COUNT;
        if (feeBalance < swapThreshold && !taxesEnded) return;

        uint256 amountToSwap = feeBalance > swapThreshold ? swapThreshold : feeBalance;
        _swapBack(amountToSwap);
    }

    function _swapBack(uint256 tokenAmount) internal {
        inSwap = true;

        _approve(address(this), address(router), tokenAmount);
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        uint256 ethBefore = address(this).balance;
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
        uint256 ethReceived = address(this).balance - ethBefore;

        if (ethReceived != 0) {
            (bool success,) = payable(treasury).call{value: ethReceived}("");
            if (!success) revert TreasuryTransferFailed();
        }

        inSwap = false;
        emit SwapBackExecuted(tokenAmount, ethReceived);
    }
}
