// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {KOANT} from "../src/KOANT.sol";
import {TeamVault} from "../src/TeamVault.sol";
import {MockV2Router} from "./mocks/MockV2Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract KOANTTeamVaultIntegrationTest is Test {
    address operations = makeAddr("operations");
    address treasuryBeneficiary = makeAddr("treasuryBeneficiary");
    address founder1 = makeAddr("founder1");
    address founder2 = makeAddr("founder2");
    address genesisSafe = makeAddr("genesisSafe");
    address factory = makeAddr("factory");

    MockERC20 weth;
    MockV2Router router;
    TeamVault vault;
    KOANT token;

    uint256 unlock;

    function setUp() public {
        unlock = block.timestamp + 365 days;

        vault = new TeamVault(treasuryBeneficiary, unlock);

        weth = new MockERC20("Wrapped Ether", "WETH");
        router = new MockV2Router(factory, address(weth));

        token =
            new KOANT(operations, founder1, founder2, genesisSafe, address(vault), address(router), 40_469_000 ether);

        assertEq(token.balanceOf(address(vault)), token.TEAM_VAULT_ALLOCATION());
        assertEq(token.balanceOf(treasuryBeneficiary), 0);
        assertGt(token.TEAM_VAULT_ALLOCATION(), token.MAX_WALLET());
    }

    function test_FullTeamVaultAllocationReleasesToBeneficiaryAtUnlock() public {
        vm.warp(unlock);

        vault.releaseToken(IERC20(address(token)));

        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(treasuryBeneficiary), token.TEAM_VAULT_ALLOCATION());
    }

    function test_TeamVaultReleaseDoesNotMakeBeneficiaryGenerallyMaxWalletExempt() public {
        vm.warp(unlock);
        vault.releaseToken(IERC20(address(token)));

        uint256 beneficiaryBalance = token.balanceOf(treasuryBeneficiary);

        vm.startPrank(founder1);

        vm.expectRevert(
            abi.encodeWithSelector(KOANT.MaxWalletExceeded.selector, beneficiaryBalance + 1, token.MAX_WALLET())
        );

        token.transfer(treasuryBeneficiary, 1);

        vm.stopPrank();

        assertEq(token.balanceOf(treasuryBeneficiary), beneficiaryBalance);
    }

    function test_OrdinaryRecipientStillCannotExceedMaxWallet() public {
        address ordinaryRecipient = makeAddr("ordinaryRecipient");

        vm.prank(genesisSafe);
        token.transfer(ordinaryRecipient, token.MAX_WALLET());

        vm.startPrank(founder1);

        vm.expectRevert(
            abi.encodeWithSelector(KOANT.MaxWalletExceeded.selector, token.MAX_WALLET() + 1, token.MAX_WALLET())
        );

        token.transfer(ordinaryRecipient, 1);

        vm.stopPrank();
    }
}
