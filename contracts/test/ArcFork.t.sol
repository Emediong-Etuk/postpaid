// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PostPaidEscrow} from "../PostPaidEscrow.sol";

/// @dev Optional fork test. Runs only when ARC_RPC_URL is set; otherwise returns early.
contract ArcForkTest is Test {
    address internal constant USDC = 0x3600000000000000000000000000000000000000;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal brand = makeAddr("brand");
    address internal creator = makeAddr("creator");

    /// @dev External so a failing `deal` (no discoverable balance slot) can be caught.
    function tryFund(address to, uint256 amt) external {
        deal(USDC, to, amt);
    }

    function test_ForkUsdcDecimalsAndDeploy() public {
        string memory rpc = vm.envOr("ARC_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            console.log("ARC_RPC_URL not set; skipping fork test");
            return;
        }
        vm.createSelectFork(rpc);

        assertEq(IERC20Metadata(USDC).decimals(), 6, "real USDC decimals");

        PostPaidEscrow esc = new PostPaidEscrow(IERC20(USDC), owner, feeRecipient, 100);
        assertEq(address(esc.usdc()), USDC);
        assertEq(esc.owner(), owner);
        assertEq(esc.feeRecipient(), feeRecipient);
        assertEq(esc.protocolFeeBps(), 100);

        uint256 amt = 1_000_000;
        try this.tryFund(brand, amt) {} catch {
            console.log("deal() could not fund real USDC; deploy-only check done");
            return;
        }
        if (IERC20(USDC).balanceOf(brand) < amt) {
            console.log("deal() did not credit real USDC; deploy-only check done");
            return;
        }

        string[] memory labels = new string[](1);
        labels[0] = "M1";
        uint256[] memory amts = new uint256[](1);
        amts[0] = amt;
        uint64[] memory dues = new uint64[](1);
        dues[0] = uint64(block.timestamp + 1 days);

        vm.startPrank(brand);
        IERC20(USDC).approve(address(esc), amt);
        uint256 id = esc.createDeal(creator, address(0), "Fork deal", "", labels, amts, dues, 1 hours, 1);
        vm.stopPrank();
        assertEq(IERC20(USDC).balanceOf(address(esc)), amt);

        vm.startPrank(creator);
        esc.acceptDeal(id);
        esc.submitMilestone(id, 0, "ipfs://proof");
        vm.stopPrank();

        vm.prank(brand);
        esc.approveMilestone(id, 0);
        assertEq(esc.withdrawable(creator), 990_000);
        assertEq(esc.withdrawable(feeRecipient), 10_000);

        uint256 before = IERC20(USDC).balanceOf(creator);
        vm.prank(creator);
        esc.withdraw();
        assertEq(IERC20(USDC).balanceOf(creator) - before, 990_000);
        vm.prank(feeRecipient);
        esc.withdraw();
        assertEq(IERC20(USDC).balanceOf(address(esc)), 0);
        assertEq(uint8(esc.getDeal(id).status), uint8(PostPaidEscrow.DealStatus.Closed));
    }
}
