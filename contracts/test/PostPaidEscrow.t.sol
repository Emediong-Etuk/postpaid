// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PostPaidEscrow} from "../PostPaidEscrow.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {FeeOnTransferUSDC} from "./mocks/FeeOnTransferUSDC.sol";

contract PostPaidEscrowTest is Test {
    struct P {
        address creator;
        address arbiter;
        string title;
        string briefURI;
        string[] labels;
        uint256[] amounts;
        uint64[] dueBys;
        uint32 reviewPeriod;
        uint8 maxRevisions;
    }

    MockUSDC internal usdc;
    PostPaidEscrow internal esc;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal brand = makeAddr("brand");
    address internal creator = makeAddr("creator");
    address internal arbiter = makeAddr("arbiter");
    address internal stranger = makeAddr("stranger");

    uint16 internal constant FEE = 100;
    uint256 internal constant T0 = 1_700_000_000;
    uint256 internal constant AMT = 1_000_000;
    uint32 internal constant REVIEW = 1 hours;
    uint256 internal constant DUE = T0 + 1 days;
    string internal constant PROOF = "ipfs://proof";

    // DealStatus
    uint8 internal constant OPEN = 0;
    uint8 internal constant ACTIVE = 1;
    uint8 internal constant CANCELLED = 2;
    uint8 internal constant CLOSED = 3;
    // MilestoneStatus
    uint8 internal constant PENDING = 0;
    uint8 internal constant SUBMITTED = 1;
    uint8 internal constant DISPUTED = 2;
    uint8 internal constant RELEASED = 3;
    uint8 internal constant REFUNDED = 4;
    uint8 internal constant SPLIT = 5;
    // milestoneActions bitmask
    uint8 internal constant A_SUBMIT = 1;
    uint8 internal constant A_APPROVE = 2;
    uint8 internal constant A_REVISE = 4;
    uint8 internal constant A_DISPUTE = 8;
    uint8 internal constant A_CLAIM = 16;
    uint8 internal constant A_REFUND = 32;
    uint8 internal constant A_STALE = 64;

    function setUp() public {
        vm.warp(T0);
        usdc = new MockUSDC();
        esc = new PostPaidEscrow(IERC20(address(usdc)), owner, feeRecipient, FEE);
        usdc.mint(brand, 1e24);
        vm.prank(brand);
        usdc.approve(address(esc), type(uint256).max);
        vm.label(address(esc), "escrow");
        vm.label(address(usdc), "usdc");
    }

    // ───────────────────────────── helpers ─────────────────────────────

    function _p(uint256 n) internal view returns (P memory p) {
        p.creator = creator;
        p.arbiter = arbiter;
        p.title = "Campaign";
        p.briefURI = "ipfs://brief";
        p.labels = new string[](n);
        p.amounts = new uint256[](n);
        p.dueBys = new uint64[](n);
        for (uint256 i; i < n; ++i) {
            p.labels[i] = "M";
            p.amounts[i] = AMT;
            p.dueBys[i] = uint64(block.timestamp + 1 days);
        }
        p.reviewPeriod = REVIEW;
        p.maxRevisions = 2;
    }

    function _createOn(PostPaidEscrow e, P memory p) internal returns (uint256) {
        vm.prank(brand);
        return e.createDeal(
            p.creator, p.arbiter, p.title, p.briefURI, p.labels, p.amounts, p.dueBys, p.reviewPeriod, p.maxRevisions
        );
    }

    function _create(P memory p) internal returns (uint256) {
        return _createOn(esc, p);
    }

    function _createFail(P memory p, bytes memory err) internal {
        vm.prank(brand);
        vm.expectRevert(err);
        esc.createDeal(
            p.creator, p.arbiter, p.title, p.briefURI, p.labels, p.amounts, p.dueBys, p.reviewPeriod, p.maxRevisions
        );
    }

    function _invalid(P memory p) internal {
        _createFail(p, abi.encodeWithSelector(PostPaidEscrow.InvalidParams.selector));
    }

    function _open(uint256 n, bool withArb) internal returns (uint256) {
        P memory p = _p(n);
        if (!withArb) p.arbiter = address(0);
        return _create(p);
    }

    function _active(uint256 n, bool withArb) internal returns (uint256 id) {
        id = _open(n, withArb);
        vm.prank(creator);
        esc.acceptDeal(id);
    }

    function _submit(uint256 id, uint256 i) internal {
        vm.prank(creator);
        esc.submitMilestone(id, i, PROOF);
    }

    function _submitted(bool withArb) internal returns (uint256 id) {
        id = _active(1, withArb);
        _submit(id, 0);
    }

    function _disputed(uint256 n) internal returns (uint256 id) {
        id = _active(n, true);
        _submit(id, 0);
        vm.prank(brand);
        esc.openDispute(id, 0, "bad work");
    }

    function _approve(uint256 id, uint256 i) internal {
        vm.prank(brand);
        esc.approveMilestone(id, i);
    }

    function _ee() internal {
        vm.expectEmit(true, true, true, true, address(esc));
    }

    function _dstatus(uint256 id) internal view returns (uint256) {
        return uint256(uint8(esc.getDeal(id).status));
    }

    function _mstatus(uint256 id, uint256 i) internal view returns (uint256) {
        return uint256(uint8(esc.getMilestones(id)[i].status));
    }

    /// @dev Single-deal money check: creator/brand/fee credits, deal + global escrow, solvency.
    function _money(uint256 id, uint256 c, uint256 b, uint256 f, uint256 escrowed) internal view {
        assertEq(esc.withdrawable(creator), c, "creator credit");
        assertEq(esc.withdrawable(brand), b, "brand credit");
        assertEq(esc.withdrawable(feeRecipient), f, "fee credit");
        assertEq(esc.getDeal(id).escrowed, escrowed, "deal escrowed");
        assertEq(esc.totalEscrowed(), escrowed, "totalEscrowed");
        assertEq(esc.totalWithdrawable(), c + b + f, "totalWithdrawable");
        assertEq(usdc.balanceOf(address(esc)), escrowed + c + b + f, "solvency");
    }

    function _closedCount(Vm.Log[] memory logs) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(esc) && logs[i].topics[0] == PostPaidEscrow.DealClosed.selector) ++n;
        }
    }

    function _mask(uint256 id, uint256 i) internal view returns (uint8 m, uint64 re) {
        (bool s, bool ap, bool rv, bool ds, bool ct, bool rf, bool st, uint64 r) = esc.milestoneActions(id, i);
        if (s) m |= A_SUBMIT;
        if (ap) m |= A_APPROVE;
        if (rv) m |= A_REVISE;
        if (ds) m |= A_DISPUTE;
        if (ct) m |= A_CLAIM;
        if (rf) m |= A_REFUND;
        if (st) m |= A_STALE;
        re = r;
    }

    function _expectActions(uint256 id, uint256 i, uint8 mask, uint64 re) internal view {
        (uint8 m, uint64 r) = _mask(id, i);
        assertEq(uint256(m), uint256(mask), "action mask");
        assertEq(uint256(r), uint256(re), "reviewEndsAt");
    }

    function _lenStr(uint256 n) internal pure returns (string memory) {
        return string(new bytes(n));
    }

    // ───────────────────────── constructor / config ─────────────────────────

    function test_Constructor_StoresConfig() public view {
        assertEq(address(esc.usdc()), address(usdc));
        assertEq(esc.owner(), owner);
        assertEq(esc.feeRecipient(), feeRecipient);
        assertEq(uint256(esc.protocolFeeBps()), uint256(FEE));
        assertEq(esc.nextDealId(), 1, "ids start at 1");
        assertEq(esc.totalEscrowed(), 0);
        assertEq(esc.totalWithdrawable(), 0);
        assertFalse(esc.paused());
    }

    function test_Constants() public view {
        assertEq(esc.MIN_MILESTONE(), 10_000);
        assertEq(esc.MAX_MILESTONES(), 10);
        assertEq(esc.MIN_REVIEW_PERIOD(), 5 minutes);
        assertEq(esc.MAX_REVIEW_PERIOD(), 30 days);
        assertEq(esc.MAX_REVISIONS(), 3);
        assertEq(esc.MAX_FEE_BPS(), 200);
        assertEq(esc.DISPUTE_TIMEOUT(), 14 days);
        assertEq(esc.BPS(), 10_000);
    }

    function test_Constructor_ZeroUsdcReverts() public {
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        new PostPaidEscrow(IERC20(address(0)), owner, feeRecipient, FEE);
    }

    function test_Constructor_ZeroOwnerReverts() public {
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        new PostPaidEscrow(IERC20(address(usdc)), address(0), feeRecipient, FEE);
    }

    function test_Constructor_ZeroFeeRecipientReverts() public {
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        new PostPaidEscrow(IERC20(address(usdc)), owner, address(0), FEE);
    }

    function test_Constructor_FeeAboveCapReverts() public {
        vm.expectRevert(PostPaidEscrow.FeeTooHigh.selector);
        new PostPaidEscrow(IERC20(address(usdc)), owner, feeRecipient, 201);
    }

    function test_Constructor_FeeBoundariesAccepted() public {
        PostPaidEscrow a = new PostPaidEscrow(IERC20(address(usdc)), owner, feeRecipient, 200);
        PostPaidEscrow b = new PostPaidEscrow(IERC20(address(usdc)), owner, feeRecipient, 0);
        assertEq(uint256(a.protocolFeeBps()), 200);
        assertEq(uint256(b.protocolFeeBps()), 0);
    }

    // ───────────────────────────── 1. create ─────────────────────────────

    function test_Create_HappyPath_StoresEverythingAndEmits() public {
        P memory p = _p(2);
        p.amounts[0] = 600_000;
        p.amounts[1] = 400_000;
        p.dueBys[0] = uint64(T0 + 1 days);
        p.dueBys[1] = uint64(T0 + 2 days);
        p.labels[0] = "Launch thread";
        p.labels[1] = "Follow-up";
        p.title = "PostPaid launch";
        p.maxRevisions = 3;
        uint256 balBefore = usdc.balanceOf(brand);

        _ee();
        emit PostPaidEscrow.DealCreated(1, brand, creator, arbiter, 1_000_000, FEE, REVIEW, "PostPaid launch", "ipfs://brief");
        uint256 id = _create(p);

        assertEq(id, 1);
        assertEq(esc.nextDealId(), 2);
        assertEq(balBefore - usdc.balanceOf(brand), 1_000_000, "brand paid exactly total");
        assertEq(usdc.balanceOf(address(esc)), 1_000_000);
        assertEq(esc.totalEscrowed(), 1_000_000);
        assertEq(esc.totalWithdrawable(), 0);

        PostPaidEscrow.Deal memory d = esc.getDeal(id);
        assertEq(d.brand, brand);
        assertEq(d.creator, creator);
        assertEq(d.arbiter, arbiter);
        assertEq(uint256(d.createdAt), T0);
        assertEq(uint256(d.reviewPeriod), uint256(REVIEW));
        assertEq(uint256(d.feeBps), uint256(FEE));
        assertEq(uint256(d.maxRevisions), 3);
        assertEq(uint256(uint8(d.status)), uint256(OPEN));
        assertEq(d.totalAmount, 1_000_000);
        assertEq(d.escrowed, 1_000_000);
        assertEq(d.title, "PostPaid launch");
        assertEq(d.briefURI, "ipfs://brief");

        PostPaidEscrow.Milestone[] memory ms = esc.getMilestones(id);
        assertEq(ms.length, 2);
        assertEq(ms[0].label, "Launch thread");
        assertEq(ms[0].amount, 600_000);
        assertEq(uint256(ms[0].dueBy), T0 + 1 days);
        assertEq(ms[1].label, "Follow-up");
        assertEq(ms[1].amount, 400_000);
        assertEq(uint256(ms[1].dueBy), T0 + 2 days);
        for (uint256 i; i < 2; ++i) {
            assertEq(uint256(ms[i].submittedAt), 0);
            assertEq(uint256(ms[i].disputedAt), 0);
            assertEq(uint256(ms[i].revisionsUsed), 0);
            assertEq(uint256(uint8(ms[i].status)), uint256(PENDING));
            assertEq(ms[i].proofURI, "");
        }
    }

    function test_Create_IndexesAndSequentialIds() public {
        uint256 id1 = _open(1, true);
        uint256 id2 = _open(1, false);
        assertEq(id1, 1);
        assertEq(id2, 2);
        uint256[] memory b = esc.dealsOfBrand(brand);
        assertEq(b.length, 2);
        assertEq(b[0], 1);
        assertEq(b[1], 2);
        uint256[] memory c = esc.dealsOfCreator(creator);
        assertEq(c.length, 2);
        uint256[] memory a = esc.dealsOfArbiter(arbiter);
        assertEq(a.length, 1, "only the arbitered deal is indexed");
        assertEq(a[0], 1);
        assertEq(esc.dealsOfArbiter(address(0)).length, 0);
    }

    function test_Create_LocksCurrentFee() public {
        vm.prank(owner);
        esc.setProtocolFee(175);
        uint256 id = _open(1, true);
        assertEq(uint256(esc.getDeal(id).feeBps), 175);
    }

    function test_Create_BoundaryValuesAccepted() public {
        P memory p = _p(10);
        p.title = _lenStr(80);
        p.briefURI = _lenStr(256);
        p.reviewPeriod = 5 minutes;
        p.maxRevisions = 3;
        for (uint256 i; i < 10; ++i) {
            p.labels[i] = _lenStr(64);
            p.amounts[i] = 10_000;
            p.dueBys[i] = uint64(block.timestamp + 1);
        }
        uint256 id = _create(p);
        assertEq(esc.getMilestones(id).length, 10);
        assertEq(esc.getDeal(id).totalAmount, 100_000);

        P memory q = _p(1);
        q.briefURI = "";
        q.reviewPeriod = 30 days;
        q.arbiter = address(0);
        assertEq(_create(q), id + 1);
    }

    function test_Create_ZeroCreatorReverts() public {
        P memory p = _p(1);
        p.creator = address(0);
        _invalid(p);
    }

    function test_Create_SelfDealReverts() public {
        P memory p = _p(1);
        p.creator = brand;
        _invalid(p);
    }

    function test_Create_ArbiterIsBrandReverts() public {
        P memory p = _p(1);
        p.arbiter = brand;
        _invalid(p);
    }

    function test_Create_ArbiterIsCreatorReverts() public {
        P memory p = _p(1);
        p.arbiter = creator;
        _invalid(p);
    }

    function test_Create_ZeroMilestonesReverts() public {
        _invalid(_p(0));
    }

    function test_Create_ElevenMilestonesReverts() public {
        _invalid(_p(11));
    }

    function test_Create_AmountsLengthMismatchReverts() public {
        P memory p = _p(2);
        p.amounts = new uint256[](1);
        p.amounts[0] = AMT;
        _invalid(p);
        p.amounts = new uint256[](3);
        _invalid(p);
    }

    function test_Create_DueBysLengthMismatchReverts() public {
        P memory p = _p(2);
        p.dueBys = new uint64[](1);
        p.dueBys[0] = uint64(T0 + 1 days);
        _invalid(p);
    }

    function test_Create_AmountBelowMinimumReverts() public {
        P memory p = _p(1);
        p.amounts[0] = 9_999;
        _invalid(p);
        P memory q = _p(2);
        q.amounts[1] = 0;
        _invalid(q);
    }

    function test_Create_AmountSumOverflowReverts() public {
        P memory p = _p(2);
        p.amounts[0] = type(uint256).max;
        p.amounts[1] = 10_000;
        _invalid(p);
    }

    function test_Create_DueByNotInFutureReverts() public {
        P memory p = _p(1);
        p.dueBys[0] = uint64(T0);
        _invalid(p);
        p.dueBys[0] = uint64(T0 - 1);
        _invalid(p);
        P memory q = _p(2);
        q.dueBys[1] = uint64(T0);
        _invalid(q);
    }

    function test_Create_ReviewPeriodOutOfBoundsReverts() public {
        P memory p = _p(1);
        p.reviewPeriod = 5 minutes - 1;
        _invalid(p);
        p.reviewPeriod = 0;
        _invalid(p);
        p.reviewPeriod = 30 days + 1;
        _invalid(p);
    }

    function test_Create_TooManyRevisionsReverts() public {
        P memory p = _p(1);
        p.maxRevisions = 4;
        _invalid(p);
    }

    function test_Create_TitleBoundsRevert() public {
        P memory p = _p(1);
        p.title = "";
        _invalid(p);
        p.title = _lenStr(81);
        _invalid(p);
    }

    function test_Create_BriefTooLongReverts() public {
        P memory p = _p(1);
        p.briefURI = _lenStr(257);
        _invalid(p);
    }

    function test_Create_LabelBoundsRevert() public {
        P memory p = _p(2);
        p.labels[1] = "";
        _invalid(p);
        p.labels[1] = _lenStr(65);
        _invalid(p);
    }

    function test_Create_RevertsWhenPaused() public {
        vm.prank(owner);
        esc.pause();
        P memory p = _p(1);
        _createFail(p, abi.encodeWithSelector(Pausable.EnforcedPause.selector));
    }

    function test_Create_InsufficientAllowanceReverts() public {
        address poor = makeAddr("poor");
        usdc.mint(poor, 10 * AMT);
        vm.prank(poor);
        usdc.approve(address(esc), AMT - 1);
        P memory p = _p(1);
        vm.prank(poor);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(esc), AMT - 1, AMT));
        esc.createDeal(p.creator, p.arbiter, p.title, p.briefURI, p.labels, p.amounts, p.dueBys, p.reviewPeriod, p.maxRevisions);
    }

    function test_Create_InsufficientBalanceReverts() public {
        address poor = makeAddr("poor");
        usdc.mint(poor, AMT - 1);
        vm.prank(poor);
        usdc.approve(address(esc), type(uint256).max);
        P memory p = _p(1);
        vm.prank(poor);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, poor, AMT - 1, AMT));
        esc.createDeal(p.creator, p.arbiter, p.title, p.briefURI, p.labels, p.amounts, p.dueBys, p.reviewPeriod, p.maxRevisions);
    }

    function test_Create_FeeOnTransferTokenRevertsAmountMismatch() public {
        FeeOnTransferUSDC fot = new FeeOnTransferUSDC();
        PostPaidEscrow e = new PostPaidEscrow(IERC20(address(fot)), owner, feeRecipient, FEE);
        fot.mint(brand, 10 * AMT);
        vm.prank(brand);
        fot.approve(address(e), type(uint256).max);
        P memory p = _p(1);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.AmountMismatch.selector);
        e.createDeal(p.creator, p.arbiter, p.title, p.briefURI, p.labels, p.amounts, p.dueBys, p.reviewPeriod, p.maxRevisions);
        assertEq(e.nextDealId(), 1, "nothing persisted");
    }

    // ───────────────────────────── 2. cancel ─────────────────────────────

    function test_Cancel_RefundsAllAndEmits() public {
        uint256 id = _open(2, true);
        _ee();
        emit PostPaidEscrow.DealCancelled(id, 2 * AMT);
        vm.prank(brand);
        esc.cancelDeal(id);
        assertEq(_dstatus(id), CANCELLED);
        assertEq(_mstatus(id, 0), REFUNDED);
        assertEq(_mstatus(id, 1), REFUNDED);
        _money(id, 0, 2 * AMT, 0, 0);

        uint256 before_ = usdc.balanceOf(brand);
        vm.prank(brand);
        esc.withdraw();
        assertEq(usdc.balanceOf(brand) - before_, 2 * AMT);
        assertEq(usdc.balanceOf(address(esc)), 0);
    }

    function test_Cancel_OnlyBrand() public {
        uint256 id = _open(1, true);
        address[3] memory bad = [creator, arbiter, stranger];
        for (uint256 i; i < 3; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(PostPaidEscrow.NotBrand.selector);
            esc.cancelDeal(id);
        }
    }

    function test_Cancel_AfterAcceptanceReverts() public {
        uint256 id = _active(1, true);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.cancelDeal(id);
    }

    function test_Cancel_TwiceReverts() public {
        uint256 id = _open(1, true);
        vm.startPrank(brand);
        esc.cancelDeal(id);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.cancelDeal(id);
        vm.stopPrank();
    }

    function test_Cancel_EvenAfterDueDates() public {
        uint256 id = _open(1, true);
        vm.warp(DUE + 100 days);
        vm.prank(brand);
        esc.cancelDeal(id);
        assertEq(esc.withdrawable(brand), AMT);
    }

    function test_Cancel_DoesNotEmitDealClosed() public {
        uint256 id = _open(2, true);
        vm.recordLogs();
        vm.prank(brand);
        esc.cancelDeal(id);
        assertEq(_closedCount(vm.getRecordedLogs()), 0);
        assertEq(_dstatus(id), CANCELLED, "stays Cancelled, never Closed");
    }

    // ───────────────────────────── 3. accept ─────────────────────────────

    function test_Accept_ActivatesAndEmits() public {
        uint256 id = _open(1, true);
        _ee();
        emit PostPaidEscrow.DealAccepted(id, creator);
        vm.prank(creator);
        esc.acceptDeal(id);
        assertEq(_dstatus(id), ACTIVE);
    }

    function test_Accept_OnlyCreator() public {
        uint256 id = _open(1, true);
        address[3] memory bad = [brand, arbiter, stranger];
        for (uint256 i; i < 3; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(PostPaidEscrow.NotCreator.selector);
            esc.acceptDeal(id);
        }
    }

    function test_Accept_TwiceReverts() public {
        uint256 id = _active(1, true);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.acceptDeal(id);
    }

    function test_Accept_CancelledDealReverts() public {
        uint256 id = _open(1, true);
        vm.prank(brand);
        esc.cancelDeal(id);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.acceptDeal(id);
    }

    function test_Accept_WorksAfterDueDates() public {
        uint256 id = _open(1, true);
        vm.warp(DUE + 30 days);
        vm.prank(creator);
        esc.acceptDeal(id);
        assertEq(_dstatus(id), ACTIVE);
    }

    // ───────────────────────────── 4. submit ─────────────────────────────

    function test_Submit_HappyPath() public {
        uint256 id = _active(1, true);
        vm.warp(T0 + 123);
        _ee();
        emit PostPaidEscrow.MilestoneSubmitted(id, 0, PROOF);
        _submit(id, 0);
        PostPaidEscrow.Milestone memory m = esc.getMilestones(id)[0];
        assertEq(uint256(m.submittedAt), T0 + 123);
        assertEq(m.proofURI, PROOF);
        assertEq(uint256(uint8(m.status)), uint256(SUBMITTED));
    }

    function test_Submit_OnlyCreator() public {
        uint256 id = _active(1, true);
        address[3] memory bad = [brand, arbiter, stranger];
        for (uint256 i; i < 3; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(PostPaidEscrow.NotCreator.selector);
            esc.submitMilestone(id, 0, PROOF);
        }
    }

    function test_Submit_OpenDealReverts() public {
        uint256 id = _open(1, true);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.submitMilestone(id, 0, PROOF);
    }

    function test_Submit_CancelledDealReverts() public {
        uint256 id = _open(1, true);
        vm.prank(brand);
        esc.cancelDeal(id);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.submitMilestone(id, 0, PROOF);
    }

    function test_Submit_NonPendingReverts() public {
        uint256 id = _active(1, true);
        _submit(id, 0);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.submitMilestone(id, 0, PROOF);
    }

    function test_Submit_BoundaryAtDueByAndPastDue() public {
        uint256 id = _active(2, true);
        vm.warp(DUE + 1);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.PastDue.selector);
        esc.submitMilestone(id, 0, PROOF);
        vm.warp(DUE);
        _submit(id, 1);
        assertEq(_mstatus(id, 1), SUBMITTED);
    }

    function test_Submit_ProofLengthBounds() public {
        uint256 id = _active(4, true);
        vm.startPrank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        esc.submitMilestone(id, 0, "");
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        esc.submitMilestone(id, 0, _lenStr(281));
        esc.submitMilestone(id, 0, _lenStr(280));
        esc.submitMilestone(id, 1, "x");
        vm.stopPrank();
        assertEq(_mstatus(id, 0), SUBMITTED);
        assertEq(_mstatus(id, 1), SUBMITTED);
    }

    // ───────────────────────────── 5. approve ─────────────────────────────

    function test_Approve_CreditsCreatorAndFee() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        _ee();
        emit PostPaidEscrow.MilestoneReleased(id, 0, 990_000, 10_000, PostPaidEscrow.ReleaseReason.Approved);
        _approve(id, 0);
        assertEq(_mstatus(id, 0), RELEASED);
        assertEq(_dstatus(id), ACTIVE, "second milestone still open");
        _money(id, 990_000, 0, 10_000, AMT);
    }

    function test_Approve_OnlyBrand() public {
        uint256 id = _submitted(true);
        address[3] memory bad = [creator, arbiter, stranger];
        for (uint256 i; i < 3; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(PostPaidEscrow.NotBrand.selector);
            esc.approveMilestone(id, 0);
        }
    }

    function test_Approve_NonSubmittedReverts() public {
        uint256 id = _active(1, true);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.approveMilestone(id, 0);
    }

    function test_Approve_TwiceReverts() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        _approve(id, 0);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.approveMilestone(id, 0);
    }

    function test_Approve_DisputedReverts() public {
        uint256 id = _disputed(1);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.approveMilestone(id, 0);
    }

    function test_Approve_WorksLongAfterReviewWindow() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        vm.warp(T0 + REVIEW + 365 days);
        _approve(id, 0);
        _money(id, 990_000, 0, 10_000, AMT);
    }

    function test_Approve_CancelledDealMilestoneReverts() public {
        uint256 id = _open(1, true);
        vm.startPrank(brand);
        esc.cancelDeal(id);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.approveMilestone(id, 0);
        vm.stopPrank();
    }

    // ───────────────────────────── 6. revision ─────────────────────────────

    function test_Revision_HappyPath_KeepsLongerDueBy() public {
        uint256 id = _submitted(true);
        vm.warp(T0 + 10);
        _ee();
        emit PostPaidEscrow.RevisionRequested(id, 0, "please fix", uint64(DUE));
        vm.prank(brand);
        esc.requestRevision(id, 0, "please fix");
        PostPaidEscrow.Milestone memory m = esc.getMilestones(id)[0];
        assertEq(uint256(uint8(m.status)), uint256(PENDING));
        assertEq(uint256(m.revisionsUsed), 1);
        assertEq(uint256(m.dueBy), DUE, "dueBy already later than now+review");
        assertEq(_money_escrow(id), AMT);
    }

    function _money_escrow(uint256 id) internal view returns (uint256) {
        return esc.getDeal(id).escrowed;
    }

    function test_Revision_ExtendsShortDueByAndAllowsResubmit() public {
        P memory p = _p(1);
        p.dueBys[0] = uint64(T0 + 10 minutes);
        uint256 id = _create(p);
        vm.prank(creator);
        esc.acceptDeal(id);
        _submit(id, 0);
        vm.warp(T0 + 5 minutes);
        uint64 newDue = uint64(T0 + 5 minutes + REVIEW);
        _ee();
        emit PostPaidEscrow.RevisionRequested(id, 0, "fix", newDue);
        vm.prank(brand);
        esc.requestRevision(id, 0, "fix");
        assertEq(uint256(esc.getMilestones(id)[0].dueBy), uint256(newDue));

        vm.warp(uint256(newDue) + 1);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.PastDue.selector);
        esc.submitMilestone(id, 0, "late");

        vm.warp(newDue);
        vm.prank(creator);
        esc.submitMilestone(id, 0, "v2");
        PostPaidEscrow.Milestone memory m = esc.getMilestones(id)[0];
        assertEq(m.proofURI, "v2");
        assertEq(uint256(m.submittedAt), uint256(newDue));
        assertEq(uint256(m.revisionsUsed), 1, "resubmit keeps count");
        assertEq(uint256(uint8(m.status)), uint256(SUBMITTED));
    }

    function test_Revision_CountLimitEnforced() public {
        uint256 id = _submitted(true); // maxRevisions = 2
        for (uint256 i; i < 2; ++i) {
            vm.prank(brand);
            esc.requestRevision(id, 0, "again");
            _submit(id, 0);
        }
        assertEq(uint256(esc.getMilestones(id)[0].revisionsUsed), 2);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.NoRevisionsLeft.selector);
        esc.requestRevision(id, 0, "again");
    }

    function test_Revision_MaxZeroBlocksRevisions() public {
        P memory p = _p(1);
        p.maxRevisions = 0;
        uint256 id = _create(p);
        vm.prank(creator);
        esc.acceptDeal(id);
        _submit(id, 0);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.NoRevisionsLeft.selector);
        esc.requestRevision(id, 0, "x");
    }

    function test_Revision_WindowBoundary() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        _submit(id, 1);
        vm.warp(T0 + REVIEW);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.ReviewWindowClosed.selector);
        esc.requestRevision(id, 0, "late");
        vm.warp(T0 + REVIEW - 1);
        vm.prank(brand);
        esc.requestRevision(id, 1, "in time");
        assertEq(_mstatus(id, 1), PENDING);
    }

    function test_Revision_OnlyBrandAndSubmittedOnly() public {
        uint256 id = _submitted(true);
        address[3] memory bad = [creator, arbiter, stranger];
        for (uint256 i; i < 3; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(PostPaidEscrow.NotBrand.selector);
            esc.requestRevision(id, 0, "x");
        }
        uint256 id2 = _active(1, true);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.requestRevision(id2, 0, "x");
    }

    function test_Revision_NoteLengthBounds() public {
        uint256 id = _submitted(true);
        vm.startPrank(brand);
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        esc.requestRevision(id, 0, _lenStr(281));
        esc.requestRevision(id, 0, _lenStr(280));
        vm.stopPrank();
        _submit(id, 0);
        vm.prank(brand);
        esc.requestRevision(id, 0, ""); // empty note allowed
        assertEq(uint256(esc.getMilestones(id)[0].revisionsUsed), 2);
    }

    // ───────────────────────────── 7. dispute / resolve ─────────────────────────────

    function test_Dispute_HappyPath() public {
        uint256 id = _submitted(true);
        vm.warp(T0 + 30 minutes);
        _ee();
        emit PostPaidEscrow.DisputeOpened(id, 0, "bad work");
        vm.prank(brand);
        esc.openDispute(id, 0, "bad work");
        PostPaidEscrow.Milestone memory m = esc.getMilestones(id)[0];
        assertEq(uint256(uint8(m.status)), uint256(DISPUTED));
        assertEq(uint256(m.disputedAt), T0 + 30 minutes);
    }

    function test_Dispute_NoArbiterReverts() public {
        uint256 id = _submitted(false);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.NoArbiter.selector);
        esc.openDispute(id, 0, "x");
    }

    function test_Dispute_OnlyBrand() public {
        uint256 id = _submitted(true);
        address[3] memory bad = [creator, arbiter, stranger];
        for (uint256 i; i < 3; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(PostPaidEscrow.NotBrand.selector);
            esc.openDispute(id, 0, "x");
        }
    }

    function test_Dispute_WindowBoundary() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        _submit(id, 1);
        vm.warp(T0 + REVIEW);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.ReviewWindowClosed.selector);
        esc.openDispute(id, 0, "late");
        vm.warp(T0 + REVIEW - 1);
        vm.prank(brand);
        esc.openDispute(id, 1, "in time");
        assertEq(_mstatus(id, 1), DISPUTED);
    }

    function test_Dispute_NonSubmittedReverts() public {
        uint256 id = _active(1, true);
        vm.prank(brand);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.openDispute(id, 0, "x");
    }

    function test_Dispute_ReasonLengthBounds() public {
        uint256 id = _active(3, true);
        _submit(id, 0);
        _submit(id, 1);
        vm.startPrank(brand);
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        esc.openDispute(id, 0, _lenStr(281));
        esc.openDispute(id, 0, _lenStr(280));
        esc.openDispute(id, 1, "");
        vm.stopPrank();
        assertEq(_mstatus(id, 1), DISPUTED);
    }

    function _resolveCase(uint16 bps, uint256 net, uint256 brandPart, uint256 fee, uint8 expStatus) internal {
        uint256 id = _disputed(2);
        _ee();
        emit PostPaidEscrow.DisputeResolved(id, 0, bps, net, brandPart, fee);
        vm.prank(arbiter);
        esc.resolveDispute(id, 0, bps);
        assertEq(_mstatus(id, 0), expStatus);
        assertEq(_dstatus(id), ACTIVE);
        assertEq(net + brandPart + fee, AMT, "no dust lost");
        _money(id, net, brandPart, fee, AMT);
    }

    function test_Resolve_0Bps_FullRefundToBrand() public {
        _resolveCase(0, 0, 1_000_000, 0, REFUNDED);
    }

    function test_Resolve_3333Bps() public {
        _resolveCase(3333, 329_967, 666_700, 3_333, SPLIT);
    }

    function test_Resolve_5000Bps() public {
        _resolveCase(5000, 495_000, 500_000, 5_000, SPLIT);
    }

    function test_Resolve_10000Bps_FullToCreator() public {
        _resolveCase(10_000, 990_000, 0, 10_000, RELEASED);
    }

    function test_Resolve_RoundingAt333_333() public {
        P memory p = _p(2);
        p.amounts[0] = 333_333;
        uint256 id = _create(p);
        vm.prank(creator);
        esc.acceptDeal(id);
        _submit(id, 0);
        vm.prank(brand);
        esc.openDispute(id, 0, "r");
        // gross = 111_099, fee = 1_110, net = 109_989, brand = 222_234
        _ee();
        emit PostPaidEscrow.DisputeResolved(id, 0, 3333, 109_989, 222_234, 1_110);
        vm.prank(arbiter);
        esc.resolveDispute(id, 0, 3333);
        _money(id, 109_989, 222_234, 1_110, AMT);
    }

    function test_Resolve_OnlyArbiter() public {
        uint256 id = _disputed(1);
        address[4] memory bad = [brand, creator, stranger, owner];
        for (uint256 i; i < 4; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(PostPaidEscrow.NotArbiter.selector);
            esc.resolveDispute(id, 0, 5000);
        }
    }

    function test_Resolve_BpsAboveMaxReverts() public {
        uint256 id = _disputed(1);
        vm.prank(arbiter);
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        esc.resolveDispute(id, 0, 10_001);
    }

    function test_Resolve_NonDisputedAndTwiceRevert() public {
        uint256 id = _submitted(true);
        vm.prank(arbiter);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.resolveDispute(id, 0, 5000);

        uint256 id2 = _disputed(1);
        vm.startPrank(arbiter);
        esc.resolveDispute(id2, 0, 5000);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.resolveDispute(id2, 0, 5000);
        vm.stopPrank();
    }

    function test_Resolve_WorksLongAfterDisputeTimeout() public {
        uint256 id = _disputed(1);
        vm.warp(T0 + 400 days);
        vm.prank(arbiter);
        esc.resolveDispute(id, 0, 10_000);
        assertEq(_mstatus(id, 0), RELEASED);
    }

    function test_StaleDispute_Boundary() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        vm.warp(T0 + 30 minutes);
        vm.prank(brand);
        esc.openDispute(id, 0, "r"); // disputedAt = T0 + 30 min
        uint256 d0 = T0 + 30 minutes;
        vm.warp(d0 + 14 days - 1);
        vm.prank(stranger);
        vm.expectRevert(PostPaidEscrow.DisputeNotStale.selector);
        esc.resolveStaleDispute(id, 0);

        vm.warp(d0 + 14 days);
        _ee();
        emit PostPaidEscrow.DisputeResolved(id, 0, 5000, 495_000, 500_000, 5_000);
        vm.prank(stranger);
        esc.resolveStaleDispute(id, 0);
        assertEq(_mstatus(id, 0), SPLIT);
        _money(id, 495_000, 500_000, 5_000, AMT);
    }

    function test_StaleDispute_NonDisputedReverts() public {
        uint256 id = _submitted(true);
        vm.warp(T0 + 100 days);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.resolveStaleDispute(id, 0);
    }

    // ───────────────────────────── 8. timeout claim ─────────────────────────────

    function test_Timeout_BoundaryAndThirdPartyTriggersCreatorPayout() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        vm.warp(T0 + REVIEW - 1);
        vm.prank(stranger);
        vm.expectRevert(PostPaidEscrow.ReviewWindowOpen.selector);
        esc.claimAfterTimeout(id, 0);

        vm.warp(T0 + REVIEW);
        _ee();
        emit PostPaidEscrow.MilestoneReleased(id, 0, 990_000, 10_000, PostPaidEscrow.ReleaseReason.Timeout);
        vm.prank(stranger);
        esc.claimAfterTimeout(id, 0);
        assertEq(_mstatus(id, 0), RELEASED);
        _money(id, 990_000, 0, 10_000, AMT);
        assertEq(esc.withdrawable(stranger), 0, "caller gets nothing");
    }

    function test_Timeout_NonSubmittedAndTwiceRevert() public {
        uint256 id = _active(2, true);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.claimAfterTimeout(id, 0);
        _submit(id, 0);
        vm.warp(T0 + REVIEW);
        esc.claimAfterTimeout(id, 0);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.claimAfterTimeout(id, 0);
    }

    function test_Timeout_DisputedCannotBeClaimed() public {
        uint256 id = _disputed(1);
        vm.warp(T0 + 100 days);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.claimAfterTimeout(id, 0);
    }

    // ───────────────────────────── 9. refund ─────────────────────────────

    function test_Refund_BoundaryAndThirdPartyFundsGoToBrand() public {
        uint256 id = _active(2, true);
        vm.warp(DUE);
        vm.prank(stranger);
        vm.expectRevert(PostPaidEscrow.NotYetDue.selector);
        esc.refundMilestone(id, 0);

        vm.warp(DUE + 1);
        _ee();
        emit PostPaidEscrow.MilestoneRefunded(id, 0, AMT);
        vm.prank(stranger);
        esc.refundMilestone(id, 0);
        assertEq(_mstatus(id, 0), REFUNDED);
        _money(id, 0, AMT, 0, AMT);
        assertEq(esc.withdrawable(stranger), 0);
    }

    function test_Refund_NonPendingReverts() public {
        uint256 id = _active(4, true);
        _submit(id, 0); // Submitted
        _submit(id, 1);
        vm.prank(brand);
        esc.openDispute(id, 1, "d"); // Disputed
        _submit(id, 2);
        _approve(id, 2); // Released
        vm.warp(DUE + 1);
        esc.refundMilestone(id, 3); // Refunded
        for (uint256 i; i < 4; ++i) {
            vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
            esc.refundMilestone(id, i);
        }
    }

    function test_Refund_OpenCancelledAndClosedDealsRevert() public {
        uint256 openId = _open(1, true);
        uint256 cancelId = _open(1, true);
        vm.prank(brand);
        esc.cancelDeal(cancelId);
        uint256 closedId = _active(1, true);
        _submit(closedId, 0);
        _approve(closedId, 0);
        vm.warp(DUE + 10 days);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.refundMilestone(openId, 0);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.refundMilestone(cancelId, 0);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.refundMilestone(closedId, 0);
    }

    // ───────────────────────────── 10. creator exit ─────────────────────────────

    function test_Exit_RefundsOnlyPendingAndSubmittedStillApprovable() public {
        uint256 id = _active(3, true);
        _submit(id, 0);
        _ee();
        emit PostPaidEscrow.CreatorExited(id, 2 * AMT);
        vm.prank(creator);
        esc.creatorExit(id);
        assertEq(_mstatus(id, 0), SUBMITTED);
        assertEq(_mstatus(id, 1), REFUNDED);
        assertEq(_mstatus(id, 2), REFUNDED);
        assertEq(_dstatus(id), ACTIVE);
        _money(id, 0, 2 * AMT, 0, AMT);

        _approve(id, 0);
        assertEq(_dstatus(id), CLOSED);
        _money(id, 990_000, 2 * AMT, 10_000, 0);
    }

    function test_Exit_DisputedCarriesOn() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        vm.prank(brand);
        esc.openDispute(id, 0, "d");
        vm.prank(creator);
        esc.creatorExit(id);
        assertEq(_mstatus(id, 0), DISPUTED);
        assertEq(_mstatus(id, 1), REFUNDED);
        vm.prank(arbiter);
        esc.resolveDispute(id, 0, 10_000);
        assertEq(_dstatus(id), CLOSED);
        _money(id, 990_000, AMT, 10_000, 0);
    }

    function test_Exit_NoPendingReverts() public {
        uint256 id = _active(1, true);
        _submit(id, 0);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.creatorExit(id);
    }

    function test_Exit_TwiceRevertsWhenNothingPendingLeft() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        vm.startPrank(creator);
        esc.creatorExit(id);
        vm.expectRevert(PostPaidEscrow.InvalidMilestoneStatus.selector);
        esc.creatorExit(id);
        vm.stopPrank();
    }

    function test_Exit_OnlyCreatorAndActiveOnly() public {
        uint256 id = _active(1, true);
        address[3] memory bad = [brand, arbiter, stranger];
        for (uint256 i; i < 3; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(PostPaidEscrow.NotCreator.selector);
            esc.creatorExit(id);
        }
        uint256 openId = _open(1, true);
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.creatorExit(openId);

        vm.prank(creator);
        esc.creatorExit(id); // closes deal
        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.InvalidDealStatus.selector);
        esc.creatorExit(id);
    }

    function test_Exit_C6_RevisionAfterExitMakesMilestonePendingAgain_ThenSubmitRules() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        vm.prank(creator);
        esc.creatorExit(id);
        assertEq(_mstatus(id, 0), SUBMITTED);

        vm.prank(brand);
        esc.requestRevision(id, 0, "tweak");
        assertEq(_mstatus(id, 0), PENDING, "Pending again after exit");
        _expectActions(id, 0, A_SUBMIT, 0);

        // creator may resubmit before the (possibly extended) dueBy, and it is approvable
        _submit(id, 0);
        assertEq(_mstatus(id, 0), SUBMITTED);
        _approve(id, 0);
        assertEq(_dstatus(id), CLOSED);
        _money(id, 990_000, AMT, 10_000, 0);
    }

    function test_Exit_C6_PendingAfterExitIsRefundableOnceDueByPasses() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        vm.prank(creator);
        esc.creatorExit(id);
        vm.warp(T0 + 10 minutes);
        vm.prank(brand);
        esc.requestRevision(id, 0, "tweak"); // dueBy stays DUE
        vm.warp(DUE);
        vm.expectRevert(PostPaidEscrow.NotYetDue.selector);
        esc.refundMilestone(id, 0);
        vm.warp(DUE + 1);
        vm.prank(stranger);
        esc.refundMilestone(id, 0);
        assertEq(_mstatus(id, 0), REFUNDED);
        assertEq(_dstatus(id), CLOSED);
        _money(id, 0, 2 * AMT, 0, 0);
    }

    // ───────────────────────────── 11. withdraw ─────────────────────────────

    function test_Withdraw_PaysExactBalanceZeroesAndEmits() public {
        uint256 id = _active(1, true);
        _submit(id, 0);
        _approve(id, 0);
        uint256 before_ = usdc.balanceOf(creator);

        _ee();
        emit PostPaidEscrow.Withdrawn(creator, 990_000);
        vm.prank(creator);
        esc.withdraw();

        assertEq(usdc.balanceOf(creator) - before_, 990_000);
        assertEq(esc.withdrawable(creator), 0);
        assertEq(esc.totalWithdrawable(), 10_000, "only fee left credited");
        assertEq(usdc.balanceOf(address(esc)), 10_000);

        vm.prank(creator);
        vm.expectRevert(PostPaidEscrow.NothingToWithdraw.selector);
        esc.withdraw();
    }

    function test_Withdraw_NothingToWithdrawReverts() public {
        vm.prank(stranger);
        vm.expectRevert(PostPaidEscrow.NothingToWithdraw.selector);
        esc.withdraw();
    }

    function test_Withdraw_SumsCreditsAcrossDeals() public {
        uint256 a = _open(1, true);
        uint256 b = _open(2, false);
        vm.startPrank(brand);
        esc.cancelDeal(a);
        esc.cancelDeal(b);
        vm.stopPrank();
        assertEq(esc.withdrawable(brand), 3 * AMT);
        uint256 before_ = usdc.balanceOf(brand);
        vm.prank(brand);
        esc.withdraw();
        assertEq(usdc.balanceOf(brand) - before_, 3 * AMT);
        assertEq(esc.totalWithdrawable(), 0);
        assertEq(usdc.balanceOf(address(esc)), 0);
    }

    function test_Withdraw_FeeRecipientAndOthersWithdrawIndependently() public {
        uint256 id = _active(1, true);
        _submit(id, 0);
        _approve(id, 0);
        vm.prank(feeRecipient);
        esc.withdraw();
        assertEq(usdc.balanceOf(feeRecipient), 10_000);
        assertEq(esc.withdrawable(creator), 990_000, "creator credit untouched");
    }

    function test_Withdraw_BlockedTransferRevertsWithoutLosingCredit() public {
        uint256 id = _active(1, true);
        _submit(id, 0);
        _approve(id, 0);
        vm.mockCallRevert(address(usdc), abi.encodeWithSelector(IERC20.transfer.selector, creator, 990_000), "blocked");
        vm.prank(creator);
        vm.expectRevert();
        esc.withdraw();
        assertEq(esc.withdrawable(creator), 990_000);
        assertEq(esc.totalWithdrawable(), 1_000_000);
        vm.clearMockedCalls();
        vm.prank(creator);
        esc.withdraw();
        assertEq(usdc.balanceOf(creator), 990_000);
    }

    function test_Withdraw_ReentrancyIsBlockedAndPaysOnce() public {
        HookUSDC hk = new HookUSDC();
        PostPaidEscrow e = new PostPaidEscrow(IERC20(address(hk)), owner, feeRecipient, FEE);
        ReentrantWithdrawer atk = new ReentrantWithdrawer(e);
        hk.setHook(address(atk));
        hk.mint(brand, 10 * AMT);
        vm.prank(brand);
        hk.approve(address(e), type(uint256).max);

        P memory p = _p(1);
        p.creator = address(atk);
        uint256 id = _createOn(e, p);
        atk.acceptAndSubmit(id);
        vm.prank(brand);
        e.approveMilestone(id, 0);
        assertEq(e.withdrawable(address(atk)), 990_000);

        atk.withdraw();
        assertTrue(atk.reentered(), "hook fired during transfer");
        assertFalse(atk.innerOk(), "re-entrant withdraw must fail");
        assertEq(bytes4(atk.innerErr()), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(hk.balanceOf(address(atk)), 990_000, "paid exactly once");
        assertEq(hk.balanceOf(address(e)), 10_000);
        assertEq(e.withdrawable(address(atk)), 0);
    }

    // ───────────────────────────── 12. fees ─────────────────────────────

    function test_Fees_ChangeDoesNotAffectExistingDeals() public {
        uint256 id1 = _active(1, true);
        vm.prank(owner);
        esc.setProtocolFee(200);
        uint256 id2 = _active(1, true);
        assertEq(uint256(esc.getDeal(id1).feeBps), 100);
        assertEq(uint256(esc.getDeal(id2).feeBps), 200);
        _submit(id1, 0);
        _submit(id2, 0);
        _approve(id1, 0);
        assertEq(esc.withdrawable(feeRecipient), 10_000);
        assertEq(esc.withdrawable(creator), 990_000);
        _approve(id2, 0);
        assertEq(esc.withdrawable(feeRecipient), 30_000);
        assertEq(esc.withdrawable(creator), 990_000 + 980_000);
        assertEq(esc.totalWithdrawable(), 2 * AMT);
        assertEq(esc.totalEscrowed(), 0);
    }

    function test_Fees_RoundingDownAt333_333() public {
        P memory p = _p(1);
        p.amounts[0] = 333_333;
        uint256 id = _create(p);
        vm.prank(creator);
        esc.acceptDeal(id);
        _submit(id, 0);
        _ee();
        emit PostPaidEscrow.MilestoneReleased(id, 0, 330_000, 3_333, PostPaidEscrow.ReleaseReason.Approved);
        _approve(id, 0);
        assertEq(esc.withdrawable(creator), 330_000);
        assertEq(esc.withdrawable(feeRecipient), 3_333);
        assertEq(esc.totalWithdrawable(), 333_333);
    }

    function test_Fees_ZeroFeeDeal() public {
        vm.prank(owner);
        esc.setProtocolFee(0);
        uint256 id = _active(1, true);
        _submit(id, 0);
        _approve(id, 0);
        _money(id, AMT, 0, 0, 0);
    }

    function test_Fees_SetProtocolFeeBoundsAndEvent() public {
        _ee();
        emit PostPaidEscrow.ProtocolFeeUpdated(100, 200);
        vm.prank(owner);
        esc.setProtocolFee(200);
        assertEq(uint256(esc.protocolFeeBps()), 200);
        vm.prank(owner);
        vm.expectRevert(PostPaidEscrow.FeeTooHigh.selector);
        esc.setProtocolFee(201);
        vm.prank(owner);
        vm.expectRevert(PostPaidEscrow.FeeTooHigh.selector);
        esc.setProtocolFee(type(uint16).max);
        assertEq(uint256(esc.protocolFeeBps()), 200);
    }

    function test_Fees_SetFeeRecipientAffectsFutureCreditsOnly() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        _submit(id, 1);
        _approve(id, 0);
        address newRecipient = makeAddr("newRecipient");
        _ee();
        emit PostPaidEscrow.FeeRecipientUpdated(feeRecipient, newRecipient);
        vm.prank(owner);
        esc.setFeeRecipient(newRecipient);
        assertEq(esc.feeRecipient(), newRecipient);
        _approve(id, 1);
        assertEq(esc.withdrawable(feeRecipient), 10_000, "old keeps earlier credit");
        assertEq(esc.withdrawable(newRecipient), 10_000);
    }

    function test_Fees_SetFeeRecipientZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        esc.setFeeRecipient(address(0));
    }

    // ───────────────────────────── 13. auto-close ─────────────────────────────

    function _assertClosedOnce(uint256 id) internal view {
        assertEq(_closedCount(vm.getRecordedLogs()), 1, "exactly one DealClosed");
        assertEq(_dstatus(id), CLOSED);
        assertEq(esc.getDeal(id).escrowed, 0);
    }

    function test_Close_ViaApprove_OnlyWhenLastMilestoneTerminal() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        _submit(id, 1);
        vm.recordLogs();
        _approve(id, 0);
        assertEq(_closedCount(vm.getRecordedLogs()), 0, "not closed yet");
        assertEq(_dstatus(id), ACTIVE);
        _ee();
        emit PostPaidEscrow.DealClosed(id);
        _approve(id, 1);
        assertEq(_dstatus(id), CLOSED);
    }

    function test_Close_ViaTimeoutClaim() public {
        uint256 id = _submitted(true);
        vm.warp(T0 + REVIEW);
        vm.recordLogs();
        esc.claimAfterTimeout(id, 0);
        _assertClosedOnce(id);
    }

    function test_Close_ViaRefund() public {
        uint256 id = _active(1, true);
        vm.warp(DUE + 1);
        vm.recordLogs();
        esc.refundMilestone(id, 0);
        _assertClosedOnce(id);
    }

    function test_Close_ViaResolveDispute() public {
        uint256 id = _disputed(1);
        vm.recordLogs();
        vm.prank(arbiter);
        esc.resolveDispute(id, 0, 5000);
        _assertClosedOnce(id);
    }

    function test_Close_ViaResolveStaleDispute() public {
        uint256 id = _disputed(1);
        vm.warp(T0 + 14 days);
        vm.recordLogs();
        esc.resolveStaleDispute(id, 0);
        _assertClosedOnce(id);
    }

    function test_Close_ViaCreatorExit() public {
        uint256 id = _active(2, true);
        vm.recordLogs();
        _ee();
        emit PostPaidEscrow.CreatorExited(id, 2 * AMT);
        vm.prank(creator);
        esc.creatorExit(id);
        _assertClosedOnce(id);
        _money(id, 0, 2 * AMT, 0, 0);
    }

    function test_Close_MixedTerminalStatesClosesOnLast() public {
        uint256 id = _active(3, true);
        _submit(id, 0);
        _submit(id, 1);
        _approve(id, 0);
        vm.prank(brand);
        esc.openDispute(id, 1, "d");
        vm.prank(arbiter);
        esc.resolveDispute(id, 1, 5000);
        assertEq(_dstatus(id), ACTIVE, "M2 still pending");
        vm.warp(DUE + 1);
        vm.recordLogs();
        esc.refundMilestone(id, 2);
        _assertClosedOnce(id);
        // M0: 990k/10k fee ; M1: 495k/5k fee/500k brand ; M2: 1M brand
        _money(id, 990_000 + 495_000, 500_000 + AMT, 15_000, 0);
    }

    function test_Close_NotWhileSubmittedOrDisputedRemain() public {
        uint256 id = _active(3, true);
        _submit(id, 0);
        _submit(id, 1);
        vm.prank(brand);
        esc.openDispute(id, 1, "d");
        vm.prank(creator);
        esc.creatorExit(id); // M2 refunded; M0 submitted, M1 disputed
        assertEq(_dstatus(id), ACTIVE);
        _approve(id, 0);
        assertEq(_dstatus(id), ACTIVE, "disputed M1 keeps the deal open");
    }

    // ───────────────────────────── 14. pause ─────────────────────────────

    function test_Pause_OnlyBlocksCreateDeal() public {
        uint256 dOpen = _open(1, true);
        uint256 dCancel = _open(1, true);
        uint256 dA = _active(3, true);
        uint256 dB = _active(2, true);
        uint256 dC = _active(1, true);
        uint256 dD = _active(1, true);
        _submit(dA, 0);
        _submit(dA, 1);
        _submit(dA, 2);
        _submit(dB, 0);
        _submit(dD, 0);

        vm.prank(owner);
        esc.pause();
        assertTrue(esc.paused());

        P memory p = _p(1);
        _createFail(p, abi.encodeWithSelector(Pausable.EnforcedPause.selector));

        vm.prank(creator);
        esc.acceptDeal(dOpen);
        vm.prank(brand);
        esc.cancelDeal(dCancel);
        _approve(dA, 0);
        vm.prank(brand);
        esc.requestRevision(dA, 1, "r");
        _submit(dA, 1);
        vm.prank(brand);
        esc.openDispute(dA, 2, "d");
        vm.prank(arbiter);
        esc.resolveDispute(dA, 2, 5000);
        vm.prank(brand);
        esc.openDispute(dD, 0, "d");
        vm.prank(creator);
        esc.creatorExit(dC);
        assertEq(_dstatus(dC), CLOSED);

        vm.warp(T0 + 14 days + 1);
        esc.claimAfterTimeout(dB, 0);
        esc.refundMilestone(dB, 1);
        esc.resolveStaleDispute(dD, 0);
        assertEq(_dstatus(dB), CLOSED);
        assertEq(_dstatus(dD), CLOSED);

        vm.prank(creator);
        esc.withdraw();
        vm.prank(brand);
        esc.withdraw();
        vm.prank(feeRecipient);
        esc.withdraw();

        vm.startPrank(owner);
        esc.setProtocolFee(150);
        esc.setFeeRecipient(stranger);
        vm.stopPrank();
        assertTrue(esc.paused(), "still paused");

        vm.prank(owner);
        esc.unpause();
        assertEq(_create(_p(1)), 7);
    }

    function test_Pause_Events_And_StateGuards() public {
        vm.expectEmit(false, false, false, true, address(esc));
        emit Pausable.Paused(owner);
        vm.prank(owner);
        esc.pause();
        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        esc.pause();
        vm.expectEmit(false, false, false, true, address(esc));
        emit Pausable.Unpaused(owner);
        vm.prank(owner);
        esc.unpause();
        vm.prank(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        esc.unpause();
    }

    // ───────────────────────────── 15. access control (table) ─────────────────────────────

    uint256 internal constant ROWS = 14;

    function _row(uint256 r) internal returns (bytes memory cd, address allowed, bytes4 err) {
        bytes4 own = Ownable.OwnableUnauthorizedAccount.selector;
        uint256 id;
        if (r == 0) {
            id = _open(1, true);
            return (abi.encodeCall(esc.cancelDeal, (id)), brand, PostPaidEscrow.NotBrand.selector);
        } else if (r == 1) {
            id = _open(1, true);
            return (abi.encodeCall(esc.acceptDeal, (id)), creator, PostPaidEscrow.NotCreator.selector);
        } else if (r == 2) {
            id = _active(1, true);
            return (abi.encodeCall(esc.submitMilestone, (id, 0, PROOF)), creator, PostPaidEscrow.NotCreator.selector);
        } else if (r == 3) {
            id = _submitted(true);
            return (abi.encodeCall(esc.approveMilestone, (id, 0)), brand, PostPaidEscrow.NotBrand.selector);
        } else if (r == 4) {
            id = _submitted(true);
            return (abi.encodeCall(esc.requestRevision, (id, 0, "n")), brand, PostPaidEscrow.NotBrand.selector);
        } else if (r == 5) {
            id = _submitted(true);
            return (abi.encodeCall(esc.openDispute, (id, 0, "d")), brand, PostPaidEscrow.NotBrand.selector);
        } else if (r == 6) {
            id = _disputed(1);
            return (abi.encodeCall(esc.resolveDispute, (id, 0, 5000)), arbiter, PostPaidEscrow.NotArbiter.selector);
        } else if (r == 7) {
            id = _active(1, true);
            return (abi.encodeCall(esc.creatorExit, (id)), creator, PostPaidEscrow.NotCreator.selector);
        } else if (r == 8) {
            return (abi.encodeCall(esc.setProtocolFee, (uint16(150))), owner, own);
        } else if (r == 9) {
            return (abi.encodeCall(esc.setFeeRecipient, (makeAddr("newFeeRecipient"))), owner, own);
        } else if (r == 10) {
            return (abi.encodeCall(esc.pause, ()), owner, own);
        } else if (r == 11) {
            if (!esc.paused()) {
                vm.prank(owner);
                esc.pause();
            }
            return (abi.encodeCall(esc.unpause, ()), owner, own);
        } else if (r == 12) {
            return (abi.encodeCall(esc.transferOwnership, (arbiter)), owner, own);
        } else {
            vm.prank(owner);
            esc.transferOwnership(stranger);
            return (abi.encodeCall(esc.acceptOwnership, ()), stranger, own);
        }
    }

    function _checkAccess(bytes memory cd, address allowed, bytes4 errSel, string memory label) internal {
        address[6] memory roles = [owner, feeRecipient, brand, creator, arbiter, stranger];
        for (uint256 i; i < 6; ++i) {
            if (roles[i] == allowed) continue;
            vm.prank(roles[i]);
            (bool ok, bytes memory ret) = address(esc).call(cd);
            assertFalse(ok, string.concat(label, ": wrong role succeeded"));
            bytes memory exp = errSel == Ownable.OwnableUnauthorizedAccount.selector
                ? abi.encodeWithSelector(errSel, roles[i])
                : abi.encodeWithSelector(errSel);
            assertEq(ret, exp, string.concat(label, ": wrong error"));
        }
        vm.prank(allowed);
        (bool ok2,) = address(esc).call(cd);
        assertTrue(ok2, string.concat(label, ": allowed role failed"));
    }

    function test_AccessControl_Table() public {
        for (uint256 r; r < ROWS; ++r) {
            (bytes memory cd, address allowed, bytes4 err) = _row(r);
            _checkAccess(cd, allowed, err, string.concat("row ", vm.toString(r)));
        }
        assertEq(esc.owner(), stranger, "last row completed ownership transfer");
    }

    // ───────────────────────────── 16. demo scenario (§6.1) ─────────────────────────────

    function test_Demo_Scenario() public {
        address alice = makeAddr("alice"); // brand A
        address bob = makeAddr("bob"); // creator B
        address third = makeAddr("third");
        usdc.mint(alice, 900_000);
        vm.prank(alice);
        usdc.approve(address(esc), 900_000);

        P memory p;
        p.creator = bob;
        p.title = "PostPaid launch campaign";
        p.briefURI = "https://notion.so/postpaid-brief";
        p.labels = new string[](3);
        p.labels[0] = "Launch thread";
        p.labels[1] = "Follow-up thread";
        p.labels[2] = "Spaces shoutout";
        p.amounts = new uint256[](3);
        p.amounts[0] = 300_000;
        p.amounts[1] = 300_000;
        p.amounts[2] = 300_000;
        p.dueBys = new uint64[](3);
        p.dueBys[0] = uint64(T0 + 1 days);
        p.dueBys[1] = uint64(T0 + 1 days);
        p.dueBys[2] = uint64(T0 + 20 minutes);
        p.reviewPeriod = 10 minutes;
        p.maxRevisions = 1;

        vm.prank(alice);
        uint256 id = esc.createDeal(
            p.creator, p.arbiter, p.title, p.briefURI, p.labels, p.amounts, p.dueBys, p.reviewPeriod, p.maxRevisions
        );
        assertEq(id, 1);
        assertEq(usdc.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(address(esc)), 900_000);
        assertEq(esc.totalEscrowed(), 900_000);
        assertEq(_dstatus(id), OPEN);
        assertEq(uint256(esc.getDeal(id).feeBps), 100);

        vm.prank(bob);
        esc.acceptDeal(id);
        assertEq(_dstatus(id), ACTIVE);

        vm.prank(bob);
        esc.submitMilestone(id, 0, "https://x.com/bob/status/1");
        vm.prank(alice);
        esc.approveMilestone(id, 0);
        assertEq(esc.withdrawable(bob), 297_000);
        assertEq(esc.withdrawable(feeRecipient), 3_000);

        vm.prank(bob);
        esc.withdraw();
        assertEq(usdc.balanceOf(bob), 297_000);
        assertEq(esc.withdrawable(bob), 0);

        vm.prank(bob);
        esc.submitMilestone(id, 1, "https://x.com/bob/status/2");
        vm.warp(T0 + 10 minutes);
        vm.prank(third);
        esc.claimAfterTimeout(id, 1);
        assertEq(esc.withdrawable(bob), 297_000);
        assertEq(esc.withdrawable(feeRecipient), 6_000);
        assertEq(esc.totalEscrowed(), 300_000);
        assertEq(_dstatus(id), ACTIVE);

        _expectActions(id, 2, A_SUBMIT, 0); // M3 not yet refundable
        vm.warp(T0 + 20 minutes + 1);
        vm.prank(third);
        esc.refundMilestone(id, 2);
        assertEq(esc.withdrawable(alice), 300_000);
        assertEq(_dstatus(id), CLOSED);
        assertEq(esc.totalEscrowed(), 0);

        vm.prank(bob);
        esc.withdraw();
        assertEq(usdc.balanceOf(bob), 594_000);
        vm.prank(alice);
        esc.withdraw();
        assertEq(usdc.balanceOf(alice), 300_000);
        vm.prank(feeRecipient);
        esc.withdraw();
        assertEq(usdc.balanceOf(feeRecipient), 6_000);

        assertEq(usdc.balanceOf(address(esc)), 0, "contract fully drained");
        assertEq(esc.totalWithdrawable(), 0);
        assertEq(esc.totalEscrowed(), 0);
    }

    // ───────────────────────────── approved deviations: ownership ─────────────────────────────

    function test_Renounce_RevertsEvenForOwner() public {
        vm.prank(owner);
        vm.expectRevert(PostPaidEscrow.InvalidParams.selector);
        esc.renounceOwnership();
        assertEq(esc.owner(), owner);
    }

    function test_Renounce_NonOwnerRevertsUnauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        esc.renounceOwnership();
    }

    function test_Ownership_TwoStepTransferWorks() public {
        _ee();
        emit Ownable2Step.OwnershipTransferStarted(owner, arbiter);
        vm.prank(owner);
        esc.transferOwnership(arbiter);
        assertEq(esc.owner(), owner, "owner unchanged until accepted");
        assertEq(esc.pendingOwner(), arbiter);

        _ee();
        emit Ownable.OwnershipTransferred(owner, arbiter);
        vm.prank(arbiter);
        esc.acceptOwnership();
        assertEq(esc.owner(), arbiter);
        assertEq(esc.pendingOwner(), address(0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        esc.setProtocolFee(50);
        vm.prank(arbiter);
        esc.setProtocolFee(50);
        assertEq(uint256(esc.protocolFeeBps()), 50);
    }

    // ───────────────────────────── approved deviations: unknown ids / indices ─────────────────────────────

    function _dealCalls(uint256 id) internal view returns (bytes[] memory c) {
        c = new bytes[](5);
        c[0] = abi.encodeCall(esc.cancelDeal, (id));
        c[1] = abi.encodeCall(esc.acceptDeal, (id));
        c[2] = abi.encodeCall(esc.creatorExit, (id));
        c[3] = abi.encodeCall(esc.getDeal, (id));
        c[4] = abi.encodeCall(esc.getMilestones, (id));
    }

    function _idxCalls(uint256 id, uint256 i) internal view returns (bytes[] memory c) {
        c = new bytes[](9);
        c[0] = abi.encodeCall(esc.submitMilestone, (id, i, PROOF));
        c[1] = abi.encodeCall(esc.approveMilestone, (id, i));
        c[2] = abi.encodeCall(esc.requestRevision, (id, i, "n"));
        c[3] = abi.encodeCall(esc.openDispute, (id, i, "d"));
        c[4] = abi.encodeCall(esc.resolveDispute, (id, i, 5000));
        c[5] = abi.encodeCall(esc.resolveStaleDispute, (id, i));
        c[6] = abi.encodeCall(esc.claimAfterTimeout, (id, i));
        c[7] = abi.encodeCall(esc.refundMilestone, (id, i));
        c[8] = abi.encodeCall(esc.milestoneActions, (id, i));
    }

    function _allInvalid(bytes[] memory calls, string memory label) internal {
        for (uint256 k; k < calls.length; ++k) {
            (bool ok, bytes memory ret) = address(esc).call(calls[k]);
            string memory msg_ = string.concat(label, " call#", vm.toString(k));
            assertFalse(ok, msg_);
            assertEq(ret, abi.encodeWithSelector(PostPaidEscrow.InvalidParams.selector), msg_);
        }
    }

    function test_UnknownDealId_RevertsInvalidParamsEverywhere() public {
        _open(1, true); // nextDealId == 2
        uint256[4] memory bad = [uint256(0), esc.nextDealId(), esc.nextDealId() + 1, type(uint256).max];
        for (uint256 j; j < 4; ++j) {
            _allInvalid(_dealCalls(bad[j]), string.concat("deal ", vm.toString(bad[j])));
            _allInvalid(_idxCalls(bad[j], 0), string.concat("deal ", vm.toString(bad[j])));
        }
    }

    function test_UnknownDealId_BeforeAnyDealExists() public {
        _allInvalid(_dealCalls(0), "id0");
        _allInvalid(_dealCalls(1), "id1");
    }

    function test_OutOfRangeIndex_RevertsInvalidParamsEverywhere() public {
        _open(2, true);
        uint256[3] memory bad = [uint256(2), 3, type(uint256).max];
        for (uint256 j; j < 3; ++j) {
            _allInvalid(_idxCalls(1, bad[j]), string.concat("index ", vm.toString(bad[j])));
        }
    }

    // ───────────────────────────── no ETH ─────────────────────────────

    function test_NoEthAccepted() public {
        vm.deal(address(this), 10 ether);
        (bool ok,) = address(esc).call{value: 1 ether}("");
        assertFalse(ok, "no receive");
        (ok,) = address(esc).call{value: 1 ether}(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "no fallback");
        (ok,) = address(esc).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "no fallback without value");
        (ok,) = address(esc).call("");
        assertFalse(ok, "empty calldata");
        (ok,) = address(esc).call{value: 1}(abi.encodeCall(esc.withdraw, ()));
        assertFalse(ok, "withdraw is not payable");
        (ok,) = address(esc).call{value: 1}(abi.encodeCall(esc.cancelDeal, (1)));
        assertFalse(ok, "cancelDeal is not payable");
        P memory p = _p(1);
        (ok,) = address(esc).call{value: 1}(
            abi.encodeCall(
                esc.createDeal,
                (p.creator, p.arbiter, p.title, p.briefURI, p.labels, p.amounts, p.dueBys, p.reviewPeriod, p.maxRevisions)
            )
        );
        assertFalse(ok, "createDeal is not payable");
        assertEq(address(esc).balance, 0);
    }

    // ───────────────────────────── views ─────────────────────────────

    function _createAs(address who, P memory p) internal returns (uint256) {
        vm.prank(who);
        return esc.createDeal(
            p.creator, p.arbiter, p.title, p.briefURI, p.labels, p.amounts, p.dueBys, p.reviewPeriod, p.maxRevisions
        );
    }

    function test_Views_DealsOfBrandCreatorArbiter() public {
        address brand2 = makeAddr("brand2");
        address creator2 = makeAddr("creator2");
        address arbiter2 = makeAddr("arbiter2");
        usdc.mint(brand2, 10 * AMT);
        vm.prank(brand2);
        usdc.approve(address(esc), type(uint256).max);

        uint256 d1 = _createAs(brand, _p(1)); // brand, creator, arbiter
        P memory p2 = _p(1);
        p2.arbiter = address(0);
        uint256 d2 = _createAs(brand2, p2); // brand2, creator, none
        P memory p3 = _p(1);
        p3.creator = creator2;
        p3.arbiter = arbiter2;
        uint256 d3 = _createAs(brand, p3); // brand, creator2, arbiter2
        assertEq(d1, 1);
        assertEq(d2, 2);
        assertEq(d3, 3);

        uint256[] memory a = esc.dealsOfBrand(brand);
        assertEq(a.length, 2);
        assertEq(a[0], 1);
        assertEq(a[1], 3);
        a = esc.dealsOfBrand(brand2);
        assertEq(a.length, 1);
        assertEq(a[0], 2);
        a = esc.dealsOfCreator(creator);
        assertEq(a.length, 2);
        assertEq(a[0], 1);
        assertEq(a[1], 2);
        a = esc.dealsOfCreator(creator2);
        assertEq(a.length, 1);
        assertEq(a[0], 3);
        a = esc.dealsOfArbiter(arbiter);
        assertEq(a.length, 1);
        assertEq(a[0], 1);
        a = esc.dealsOfArbiter(arbiter2);
        assertEq(a.length, 1);
        assertEq(a[0], 3);
        assertEq(esc.dealsOfBrand(stranger).length, 0);
        assertEq(esc.dealsOfCreator(stranger).length, 0);
        assertEq(esc.dealsOfArbiter(stranger).length, 0);
    }

    function test_Views_GetMilestonesOrderedAndGetDealOnAnyStatus() public {
        P memory p = _p(3);
        p.labels[0] = "a";
        p.labels[1] = "b";
        p.labels[2] = "c";
        p.amounts[1] = 20_000;
        p.amounts[2] = 30_000;
        uint256 id = _create(p);
        PostPaidEscrow.Milestone[] memory ms = esc.getMilestones(id);
        assertEq(ms.length, 3);
        assertEq(ms[0].label, "a");
        assertEq(ms[1].label, "b");
        assertEq(ms[2].label, "c");
        assertEq(ms[1].amount, 20_000);
        assertEq(ms[2].amount, 30_000);
        vm.prank(brand);
        esc.cancelDeal(id);
        assertEq(esc.getDeal(id).totalAmount, AMT + 50_000, "deal still readable after cancel");
        assertEq(esc.getMilestones(id).length, 3);
    }

    // ───────────────────────────── milestoneActions ─────────────────────────────

    function _withRevisions(uint8 maxRev, bool withArb) internal returns (uint256 id) {
        P memory p = _p(1);
        p.maxRevisions = maxRev;
        if (!withArb) p.arbiter = address(0);
        id = _create(p);
        vm.prank(creator);
        esc.acceptDeal(id);
        _submit(id, 0);
    }

    function test_Actions_OpenAndCancelledDealsAllFalse() public {
        uint256 id = _open(1, true);
        _expectActions(id, 0, 0, 0);
        vm.warp(DUE + 1);
        _expectActions(id, 0, 0, 0); // past due but deal not Active => no refund
        uint256 id2 = _open(1, true);
        vm.prank(brand);
        esc.cancelDeal(id2);
        _expectActions(id2, 0, 0, 0);
    }

    function test_Actions_PendingBeforeAndAfterDue() public {
        uint256 id = _active(1, true);
        _expectActions(id, 0, A_SUBMIT, 0);
        vm.warp(DUE);
        _expectActions(id, 0, A_SUBMIT, 0);
        vm.warp(DUE + 1);
        _expectActions(id, 0, A_REFUND, 0);
    }

    function test_Actions_SubmittedWithArbiterAndRevisions() public {
        uint256 id = _withRevisions(2, true);
        uint64 re = uint64(T0 + REVIEW);
        _expectActions(id, 0, A_APPROVE | A_REVISE | A_DISPUTE, re);
        vm.warp(T0 + REVIEW - 1);
        _expectActions(id, 0, A_APPROVE | A_REVISE | A_DISPUTE, re);
        vm.warp(T0 + REVIEW);
        _expectActions(id, 0, A_APPROVE | A_CLAIM, re);
        vm.warp(T0 + REVIEW + 30 days);
        _expectActions(id, 0, A_APPROVE | A_CLAIM, re);
    }

    function test_Actions_SubmittedWithoutArbiter() public {
        uint256 id = _withRevisions(2, false);
        uint64 re = uint64(T0 + REVIEW);
        _expectActions(id, 0, A_APPROVE | A_REVISE, re);
        vm.warp(T0 + REVIEW);
        _expectActions(id, 0, A_APPROVE | A_CLAIM, re);
    }

    function test_Actions_SubmittedWithoutRevisionsLeft() public {
        uint256 id = _withRevisions(0, true);
        uint64 re = uint64(T0 + REVIEW);
        _expectActions(id, 0, A_APPROVE | A_DISPUTE, re);
        uint256 id2 = _withRevisions(0, false);
        _expectActions(id2, 0, A_APPROVE, re);
        vm.warp(T0 + REVIEW);
        _expectActions(id, 0, A_APPROVE | A_CLAIM, re);
        _expectActions(id2, 0, A_APPROVE | A_CLAIM, re);
    }

    function test_Actions_RevisionsExhaustedAfterUse() public {
        uint256 id = _withRevisions(1, true);
        _expectActions(id, 0, A_APPROVE | A_REVISE | A_DISPUTE, uint64(T0 + REVIEW));
        vm.prank(brand);
        esc.requestRevision(id, 0, "r");
        _expectActions(id, 0, A_SUBMIT, 0);
        vm.warp(T0 + 100);
        _submit(id, 0);
        _expectActions(id, 0, A_APPROVE | A_DISPUTE, uint64(T0 + 100 + REVIEW));
    }

    function test_Actions_DisputedBeforeAndAfter14Days() public {
        uint256 id = _active(1, true);
        _submit(id, 0);
        vm.warp(T0 + 10 minutes);
        vm.prank(brand);
        esc.openDispute(id, 0, "d");
        uint256 d0 = T0 + 10 minutes;
        _expectActions(id, 0, 0, 0);
        vm.warp(d0 + 14 days - 1);
        _expectActions(id, 0, 0, 0);
        vm.warp(d0 + 14 days);
        _expectActions(id, 0, A_STALE, 0);
        vm.warp(d0 + 100 days);
        _expectActions(id, 0, A_STALE, 0);
    }

    function test_Actions_TerminalStatesAllFalse() public {
        uint256 id = _active(4, true);
        _submit(id, 0);
        _submit(id, 1);
        _submit(id, 2);
        _approve(id, 0); // Released
        vm.prank(brand);
        esc.openDispute(id, 1, "d");
        vm.prank(arbiter);
        esc.resolveDispute(id, 1, 4000); // Split
        vm.prank(brand);
        esc.openDispute(id, 2, "d");
        vm.prank(arbiter);
        esc.resolveDispute(id, 2, 0); // Refunded via dispute
        vm.warp(DUE + 1);
        esc.refundMilestone(id, 3); // Refunded; deal Closed
        assertEq(_dstatus(id), CLOSED);
        vm.warp(DUE + 100 days);
        for (uint256 i; i < 4; ++i) {
            _expectActions(id, i, 0, 0);
        }
    }

    function test_Actions_AfterCreatorExitRefundedAllFalse() public {
        uint256 id = _active(2, true);
        _submit(id, 0);
        vm.prank(creator);
        esc.creatorExit(id);
        vm.warp(DUE + 5 days);
        _expectActions(id, 1, 0, 0);
    }

    function test_Actions_IgnoreCaller() public {
        uint256 id = _withRevisions(2, true);
        address[6] memory who = [owner, feeRecipient, brand, creator, arbiter, stranger];
        for (uint256 i; i < 6; ++i) {
            vm.prank(who[i]);
            (uint8 m, uint64 re) = _mask(id, 0);
            assertEq(uint256(m), uint256(A_APPROVE | A_REVISE | A_DISPUTE));
            assertEq(uint256(re), T0 + REVIEW);
        }
    }

    // ───────────────────────────── fuzz ─────────────────────────────

    function _splitMath(uint256 amount, uint256 feeBps, uint256 bps)
        internal
        pure
        returns (uint256 net, uint256 brandPart, uint256 fee)
    {
        uint256 gross = amount * bps / 10_000;
        brandPart = amount - gross;
        fee = gross * feeBps / 10_000;
        net = gross - fee;
    }

    function _submittedDeal(uint256 amount, uint256 feeBps, bool withArb) internal returns (uint256 id) {
        vm.prank(owner);
        esc.setProtocolFee(uint16(feeBps));
        P memory p = _p(1);
        p.amounts[0] = amount;
        if (!withArb) p.arbiter = address(0);
        id = _create(p);
        vm.prank(creator);
        esc.acceptDeal(id);
        _submit(id, 0);
    }

    /// @dev Half the runs probe within +-2s of the boundary, the other half roam [lo, hi].
    function _pick(uint256 t, uint256 near, uint256 boundary, uint256 lo, uint256 hi) internal pure returns (uint256 x) {
        if (near % 2 == 0) {
            x = boundary + ((near / 2) % 5) - 2;
            if (x < lo) x = lo;
            if (x > hi) x = hi;
        } else {
            x = bound(t, lo, hi);
        }
    }

    function testFuzz_Split_ConservesEveryUnit(uint256 amount, uint256 feeBps, uint256 creatorBps) public {
        amount = bound(amount, esc.MIN_MILESTONE(), 1e15);
        feeBps = bound(feeBps, 0, 200);
        creatorBps = bound(creatorBps, 0, 10_000);
        uint256 id = _submittedDeal(amount, feeBps, true);
        vm.prank(brand);
        esc.openDispute(id, 0, "d");

        (uint256 net, uint256 brandPart, uint256 fee) = _splitMath(amount, feeBps, creatorBps);
        assertEq(net + fee + brandPart, amount, "no dust lost");

        _ee();
        emit PostPaidEscrow.DisputeResolved(id, 0, uint16(creatorBps), net, brandPart, fee);
        vm.prank(arbiter);
        esc.resolveDispute(id, 0, uint16(creatorBps));

        _money(id, net, brandPart, fee, 0);
        uint256 expStatus = creatorBps == 10_000 ? RELEASED : creatorBps == 0 ? REFUNDED : SPLIT;
        assertEq(_mstatus(id, 0), expStatus);
        assertEq(_dstatus(id), CLOSED);
        assertEq(esc.withdrawable(creator) + esc.withdrawable(brand) + esc.withdrawable(feeRecipient), amount);
        assertEq(esc.totalWithdrawable(), amount);
    }

    function testFuzz_StaleDispute_ConservesEveryUnit(uint256 amount, uint256 feeBps) public {
        amount = bound(amount, esc.MIN_MILESTONE(), 1e15);
        feeBps = bound(feeBps, 0, 200);
        uint256 id = _submittedDeal(amount, feeBps, true);
        vm.prank(brand);
        esc.openDispute(id, 0, "d");
        vm.warp(T0 + 14 days);
        (uint256 net, uint256 brandPart, uint256 fee) = _splitMath(amount, feeBps, 5000);
        _ee();
        emit PostPaidEscrow.DisputeResolved(id, 0, 5000, net, brandPart, fee);
        vm.prank(stranger);
        esc.resolveStaleDispute(id, 0);
        _money(id, net, brandPart, fee, 0);
        assertEq(net + brandPart + fee, amount);
    }

    function testFuzz_Release_FeeMath(uint256 amount, uint256 feeBps, bool viaTimeout) public {
        amount = bound(amount, esc.MIN_MILESTONE(), 1e15);
        feeBps = bound(feeBps, 0, 200);
        uint256 id = _submittedDeal(amount, feeBps, true);
        uint256 fee = amount * feeBps / 10_000;
        uint256 net = amount - fee;
        PostPaidEscrow.ReleaseReason reason =
            viaTimeout ? PostPaidEscrow.ReleaseReason.Timeout : PostPaidEscrow.ReleaseReason.Approved;
        _ee();
        emit PostPaidEscrow.MilestoneReleased(id, 0, net, fee, reason);
        if (viaTimeout) {
            vm.warp(T0 + REVIEW);
            vm.prank(stranger);
            esc.claimAfterTimeout(id, 0);
        } else {
            _approve(id, 0);
        }
        assertEq(net + fee, amount);
        assertLe(fee, amount * 200 / 10_000, "fee never exceeds the 2% cap");
        _money(id, net, 0, fee, 0);
        assertEq(_dstatus(id), CLOSED);
    }

    function testFuzz_Refund_FullAmountNoFee(uint256 amount, uint256 feeBps) public {
        amount = bound(amount, esc.MIN_MILESTONE(), 1e15);
        feeBps = bound(feeBps, 0, 200);
        vm.prank(owner);
        esc.setProtocolFee(uint16(feeBps));
        P memory p = _p(1);
        p.amounts[0] = amount;
        uint256 id = _create(p);
        vm.prank(creator);
        esc.acceptDeal(id);
        vm.warp(DUE + 1);
        _ee();
        emit PostPaidEscrow.MilestoneRefunded(id, 0, amount);
        vm.prank(stranger);
        esc.refundMilestone(id, 0);
        _money(id, 0, amount, 0, 0);
    }

    function testFuzz_Create_PullsExactSum(uint256 a0, uint256 a1, uint256 a2) public {
        P memory p = _p(3);
        p.amounts[0] = bound(a0, 10_000, 1e15);
        p.amounts[1] = bound(a1, 10_000, 1e15);
        p.amounts[2] = bound(a2, 10_000, 1e15);
        uint256 total = p.amounts[0] + p.amounts[1] + p.amounts[2];
        uint256 balBefore = usdc.balanceOf(brand);
        uint256 id = _create(p);
        assertEq(balBefore - usdc.balanceOf(brand), total);
        assertEq(esc.getDeal(id).totalAmount, total);
        assertEq(esc.getDeal(id).escrowed, total);
        assertEq(esc.totalEscrowed(), total);
        assertEq(usdc.balanceOf(address(esc)), total);
    }

    function testFuzz_Create_DueByBoundary(uint256 dueBy, uint256 near) public {
        dueBy = _pick(dueBy, near, T0, 1, T0 + 10 days);
        P memory p = _p(1);
        p.dueBys[0] = uint64(dueBy);
        if (dueBy <= T0) {
            _invalid(p);
        } else {
            uint256 id = _create(p);
            assertEq(uint256(esc.getMilestones(id)[0].dueBy), dueBy);
        }
    }

    function testFuzz_SubmitRefundBoundary(uint256 t, uint256 near) public {
        t = _pick(t, near, DUE, T0, DUE + 3 days);
        uint256 id = _active(1, true);
        vm.warp(t);
        (uint8 m,) = _mask(id, 0);
        if (t <= DUE) {
            assertEq(uint256(m), uint256(A_SUBMIT));
            vm.expectRevert(PostPaidEscrow.NotYetDue.selector);
            esc.refundMilestone(id, 0);
            _submit(id, 0);
            assertEq(_mstatus(id, 0), SUBMITTED);
        } else {
            assertEq(uint256(m), uint256(A_REFUND));
            vm.prank(creator);
            vm.expectRevert(PostPaidEscrow.PastDue.selector);
            esc.submitMilestone(id, 0, PROOF);
            esc.refundMilestone(id, 0);
            assertEq(_mstatus(id, 0), REFUNDED);
            assertEq(esc.withdrawable(brand), AMT);
        }
    }

    /// @dev Deal submitted at T0 so reviewEnd = T0 + REVIEW; returns whether `t` is inside the window.
    function _atReviewTime(uint256 t, uint256 near) internal returns (uint256 id, bool inside) {
        t = _pick(t, near, T0 + REVIEW, T0, T0 + REVIEW + 2 days);
        id = _submitted(true);
        vm.warp(t);
        inside = t < T0 + REVIEW;
    }

    function testFuzz_ReviewBoundary_Revision(uint256 t, uint256 near) public {
        (uint256 id, bool inside) = _atReviewTime(t, near);
        if (inside) {
            vm.prank(stranger);
            vm.expectRevert(PostPaidEscrow.ReviewWindowOpen.selector);
            esc.claimAfterTimeout(id, 0);
            vm.prank(brand);
            esc.requestRevision(id, 0, "r");
            assertEq(_mstatus(id, 0), PENDING);
        } else {
            vm.prank(brand);
            vm.expectRevert(PostPaidEscrow.ReviewWindowClosed.selector);
            esc.requestRevision(id, 0, "r");
            vm.prank(stranger);
            esc.claimAfterTimeout(id, 0);
            assertEq(_mstatus(id, 0), RELEASED);
        }
    }

    function testFuzz_ReviewBoundary_Dispute(uint256 t, uint256 near) public {
        (uint256 id, bool inside) = _atReviewTime(t, near);
        if (inside) {
            vm.prank(brand);
            esc.openDispute(id, 0, "d");
            assertEq(_mstatus(id, 0), DISPUTED);
        } else {
            vm.prank(brand);
            vm.expectRevert(PostPaidEscrow.ReviewWindowClosed.selector);
            esc.openDispute(id, 0, "d");
            _approve(id, 0); // approval has no deadline
            assertEq(_mstatus(id, 0), RELEASED);
        }
    }

    function testFuzz_StaleDisputeBoundary(uint256 t, uint256 near) public {
        uint256 d0 = T0 + 10 minutes;
        t = _pick(t, near, d0 + 14 days, d0, d0 + 16 days);
        uint256 id = _submitted(true);
        vm.warp(d0);
        vm.prank(brand);
        esc.openDispute(id, 0, "d");
        vm.warp(t);
        (uint8 m,) = _mask(id, 0);
        if (t < d0 + 14 days) {
            assertEq(uint256(m), 0);
            vm.expectRevert(PostPaidEscrow.DisputeNotStale.selector);
            esc.resolveStaleDispute(id, 0);
        } else {
            assertEq(uint256(m), uint256(A_STALE));
            esc.resolveStaleDispute(id, 0);
            assertEq(_mstatus(id, 0), SPLIT);
        }
    }

    function _settle(uint256 id, uint256 i, uint256 mode, uint256 bps) internal {
        if (mode == 0) {
            _approve(id, i);
        } else if (mode == 1) {
            vm.prank(brand);
            esc.openDispute(id, i, "d");
            vm.prank(arbiter);
            esc.resolveDispute(id, i, uint16(bps));
        }
    }

    function testFuzz_MultiMilestone_GlobalAccountingAndDrain(uint256 a0, uint256 a1, uint256 a2, uint256 feeBps, uint256 seed)
        public
    {
        feeBps = bound(feeBps, 0, 200);
        vm.prank(owner);
        esc.setProtocolFee(uint16(feeBps));
        P memory p = _p(3);
        uint256 total;
        uint256[3] memory amts = [a0, a1, a2];
        for (uint256 i; i < 3; ++i) {
            p.amounts[i] = bound(amts[i], 10_000, 1e15);
            total += p.amounts[i];
        }
        uint256 id = _create(p);
        vm.prank(creator);
        esc.acceptDeal(id);
        for (uint256 i; i < 3; ++i) _submit(id, i);

        uint256[3] memory modes;
        for (uint256 i; i < 3; ++i) {
            modes[i] = uint256(keccak256(abi.encode(seed, i))) % 3;
            if (modes[i] != 2) _settle(id, i, modes[i], uint256(keccak256(abi.encode(seed, i, "bps"))) % 10_001);
        }
        vm.warp(T0 + REVIEW);
        for (uint256 i; i < 3; ++i) {
            if (modes[i] == 2) esc.claimAfterTimeout(id, i);
        }

        assertEq(_dstatus(id), CLOSED);
        assertEq(esc.totalEscrowed(), 0);
        assertEq(esc.totalWithdrawable(), total, "all value is credited");
        assertEq(usdc.balanceOf(address(esc)), total);

        address[3] memory payees = [creator, brand, feeRecipient];
        for (uint256 i; i < 3; ++i) {
            if (esc.withdrawable(payees[i]) == 0) continue;
            vm.prank(payees[i]);
            esc.withdraw();
        }
        assertEq(usdc.balanceOf(address(esc)), 0, "fully drained");
        assertEq(esc.totalWithdrawable(), 0);
    }
}

interface IHook {
    function onTokens() external;
}

/// @dev 6-decimal token that calls back into `hook` after tokens arrive; models a re-entrant recipient.
contract HookUSDC is ERC20 {
    address public hook;

    constructor() ERC20("Hook USDC", "hUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setHook(address h) external {
        hook = h;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (hook != address(0) && to == hook && from != address(0)) IHook(hook).onTokens();
    }
}

/// @dev Creator contract that tries to re-enter withdraw() while receiving tokens.
contract ReentrantWithdrawer is IHook {
    PostPaidEscrow public immutable esc;
    bool public reentered;
    bool public innerOk;
    bytes public innerErr;

    constructor(PostPaidEscrow e) {
        esc = e;
    }

    function acceptAndSubmit(uint256 id) external {
        esc.acceptDeal(id);
        esc.submitMilestone(id, 0, "proof");
    }

    function withdraw() external {
        esc.withdraw();
    }

    function onTokens() external {
        if (reentered) return;
        reentered = true;
        try esc.withdraw() {
            innerOk = true;
        } catch (bytes memory err) {
            innerErr = err;
        }
    }
}
