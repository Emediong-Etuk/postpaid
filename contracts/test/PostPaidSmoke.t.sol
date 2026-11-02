// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PostPaidEscrow} from "../PostPaidEscrow.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 a) external { _mint(to, a); }
}

contract PostPaidSmokeTest is Test {
    MockUSDC usdc;
    PostPaidEscrow esc;
    address owner = address(0xA11CE);
    address fees = address(0xFEE);
    address brand = address(0xB0B);
    address creator = address(0xC0DE);

    function setUp() public {
        usdc = new MockUSDC();
        esc = new PostPaidEscrow(IERC20(address(usdc)), owner, fees, 200);
        usdc.mint(brand, 1_000_000_000);
        vm.prank(brand);
        usdc.approve(address(esc), type(uint256).max);
    }

    function _create() internal returns (uint256 id) {
        string[] memory labels = new string[](2);
        labels[0] = "A"; labels[1] = "B";
        uint256[] memory amts = new uint256[](2);
        amts[0] = 100_000_000; amts[1] = 50_000_000;
        uint64[] memory due = new uint64[](2);
        due[0] = uint64(block.timestamp + 1 days); due[1] = uint64(block.timestamp + 2 days);
        vm.prank(brand);
        id = esc.createDeal(creator, address(0), "Campaign", "ipfs://brief", labels, amts, due, 1 hours, 1);
    }

    function test_happyPathAndTimeoutAndRefund() public {
        uint256 id = _create();
        assertEq(id, 1);
        assertEq(esc.totalEscrowed(), 150_000_000);
        vm.prank(creator); esc.acceptDeal(id);
        vm.prank(creator); esc.submitMilestone(id, 0, "ipfs://proof");
        vm.prank(brand); esc.approveMilestone(id, 0);
        assertEq(esc.withdrawable(creator), 98_000_000);
        assertEq(esc.withdrawable(fees), 2_000_000);
        // milestone 1: never submitted -> refund after dueBy
        (, , , , , bool canRefund, , ) = esc.milestoneActions(id, 1);
        assertFalse(canRefund);
        vm.warp(block.timestamp + 2 days + 1);
        esc.refundMilestone(id, 1);
        assertEq(esc.withdrawable(brand), 50_000_000);
        assertEq(uint8(esc.getDeal(id).status), uint8(PostPaidEscrow.DealStatus.Closed));
        assertEq(esc.totalEscrowed(), 0);
        vm.prank(creator); esc.withdraw();
        vm.prank(brand); esc.withdraw();
        vm.prank(fees); esc.withdraw();
        assertEq(esc.totalWithdrawable(), 0);
        assertEq(usdc.balanceOf(address(esc)), 0);
    }

    function test_cancelAndTimeoutBoundary() public {
        uint256 id = _create();
        vm.prank(brand); esc.cancelDeal(id);
        assertEq(esc.withdrawable(brand), 150_000_000);
        assertEq(uint8(esc.getDeal(id).status), uint8(PostPaidEscrow.DealStatus.Cancelled));
        uint256 id2 = _create();
        vm.prank(creator); esc.acceptDeal(id2);
        vm.prank(creator); esc.submitMilestone(id2, 0, "p");
        vm.warp(block.timestamp + 1 hours - 1);
        vm.prank(brand); esc.requestRevision(id2, 0, "fix");
        vm.prank(creator); esc.submitMilestone(id2, 0, "p2");
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert(PostPaidEscrow.ReviewWindowClosed.selector);
        vm.prank(brand); esc.requestRevision(id2, 0, "late");
        esc.claimAfterTimeout(id2, 0);
        assertEq(esc.withdrawable(creator), 98_000_000);
    }

    function test_renounceDisabled() public {
        vm.prank(owner);
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        esc.renounceOwnership();
    }
}
