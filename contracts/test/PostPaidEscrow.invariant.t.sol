// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PostPaidEscrow} from "../PostPaidEscrow.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @dev Bounded-actor handler. Every action inspects on-chain state first and does nothing when
/// the action is not currently possible, so (almost) every call that proceeds succeeds.
contract PostPaidHandler is Test {
    // DealStatus
    uint8 internal constant D_OPEN = 0;
    uint8 internal constant D_ACTIVE = 1;
    uint8 internal constant D_CANCELLED = 2;
    uint8 internal constant D_CLOSED = 3;
    // MilestoneStatus
    uint8 internal constant M_PENDING = 0;
    uint8 internal constant M_DISPUTED = 2;
    uint8 internal constant M_RELEASED = 3;

    // action ids (index into `ok`)
    uint256 internal constant A_CREATE = 0;
    uint256 internal constant A_ACCEPT = 1;
    uint256 internal constant A_CANCEL = 2;
    uint256 internal constant A_SUBMIT = 3;
    uint256 internal constant A_APPROVE = 4;
    uint256 internal constant A_REVISE = 5;
    uint256 internal constant A_DISPUTE = 6;
    uint256 internal constant A_RESOLVE = 7;
    uint256 internal constant A_STALE = 8;
    uint256 internal constant A_CLAIM = 9;
    uint256 internal constant A_REFUND = 10;
    uint256 internal constant A_EXIT = 11;
    uint256 internal constant A_WITHDRAW = 12;
    uint256 internal constant A_WARP = 13;
    uint256 internal constant A_FEE = 14;
    uint256 internal constant A_PAUSE = 15;
    uint256 public constant NUM_ACTIONS = 16;

    PostPaidEscrow public immutable esc;
    MockUSDC public immutable usdc;
    address public immutable owner;
    address public immutable feeRecipient;

    address[] public brands;
    address[] public creators;
    address[] public arbiters;
    address public stranger;
    /// @dev every account that can ever be credited (incl. feeRecipient)
    address[] public actors;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256[] public dealIds;

    mapping(uint256 => mapping(uint256 => bool)) public terminalSeen;
    mapping(uint256 => mapping(uint256 => bytes32)) public terminalHash;

    /// @dev number of successful (state-changing) calls per action
    uint256[16] public ok;

    constructor(PostPaidEscrow e, MockUSDC u, address owner_, address feeRecipient_) {
        esc = e;
        usdc = u;
        owner = owner_;
        feeRecipient = feeRecipient_;
        for (uint256 i; i < 3; ++i) {
            brands.push(makeAddr(string.concat("brand", vm.toString(i))));
            creators.push(makeAddr(string.concat("creator", vm.toString(i))));
        }
        for (uint256 i; i < 2; ++i) {
            arbiters.push(makeAddr(string.concat("arbiter", vm.toString(i))));
        }
        stranger = makeAddr("stranger");
        for (uint256 i; i < 3; ++i) {
            actors.push(brands[i]);
            actors.push(creators[i]);
        }
        actors.push(arbiters[0]);
        actors.push(arbiters[1]);
        actors.push(stranger);
        actors.push(feeRecipient_);
        for (uint256 i; i < actors.length; ++i) {
            usdc.mint(actors[i], 1e30);
            vm.prank(actors[i]);
            usdc.approve(address(esc), type(uint256).max);
        }
    }

    // ───────────────────────────── views for invariants ─────────────────────────────

    function dealCount() external view returns (uint256) {
        return dealIds.length;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // ───────────────────────────── actions ─────────────────────────────

    function create(uint256 a, uint256 b, uint256 c, uint256 d) external {
        if (esc.paused() || dealIds.length >= 60) return;
        address brand = brands[a % 3];
        address creator = creators[(a / 3) % 3];
        address arbiter = (a / 9) % 3 == 0 ? address(0) : arbiters[(a / 27) % 2];
        uint256 n = bound(b, 1, 10);
        string[] memory labels = new string[](n);
        uint256[] memory amts = new uint256[](n);
        uint64[] memory dues = new uint64[](n);
        uint256 total;
        for (uint256 i; i < n; ++i) {
            uint256 h = uint256(keccak256(abi.encode(c, i)));
            labels[i] = "M";
            amts[i] = bound(h, 10_000, 5_000_000);
            dues[i] = uint64(block.timestamp + bound(h >> 128, 1 hours, 10 days));
            total += amts[i];
        }
        uint32 review = uint32(d % 5 == 0 ? bound(d >> 8, 5 minutes, 30 days) : bound(d >> 8, 5 minutes, 2 hours));
        uint8 revisions = uint8((d >> 100) % 4);
        vm.prank(brand);
        uint256 id = esc.createDeal(creator, arbiter, "T", "b", labels, amts, dues, review, revisions);
        dealIds.push(id);
        totalDeposited += total;
        ok[A_CREATE]++;
    }

    function accept(uint256 s) external {
        (bool f, uint256 id,) = _find(A_ACCEPT, s);
        if (!f) return;
        vm.prank(esc.getDeal(id).creator);
        esc.acceptDeal(id);
        _done(A_ACCEPT, id);
    }

    function cancel(uint256 s) external {
        if (_mix(s) % 12 != 0) return; // cancel is rare so deals get a chance to be accepted
        (bool f, uint256 id,) = _find(A_CANCEL, s);
        if (!f) return;
        vm.prank(esc.getDeal(id).brand);
        esc.cancelDeal(id);
        _done(A_CANCEL, id);
    }

    function submit(uint256 s) external {
        (bool f, uint256 id, uint256 j) = _find(A_SUBMIT, s);
        if (!f) return;
        vm.prank(esc.getDeal(id).creator);
        esc.submitMilestone(id, j, "ipfs://proof");
        _done(A_SUBMIT, id);
    }

    function approve(uint256 s) external {
        (bool f, uint256 id, uint256 j) = _find(A_APPROVE, s);
        if (!f) return;
        vm.prank(esc.getDeal(id).brand);
        esc.approveMilestone(id, j);
        _done(A_APPROVE, id);
    }

    function revise(uint256 s) external {
        (bool f, uint256 id, uint256 j) = _find(A_REVISE, s);
        if (!f) return;
        vm.prank(esc.getDeal(id).brand);
        esc.requestRevision(id, j, "please fix");
        _done(A_REVISE, id);
    }

    function dispute(uint256 s) external {
        (bool f, uint256 id, uint256 j) = _find(A_DISPUTE, s);
        if (!f) return;
        vm.prank(esc.getDeal(id).brand);
        esc.openDispute(id, j, "bad work");
        _done(A_DISPUTE, id);
    }

    function resolve(uint256 s, uint256 bpsSeed) external {
        if (_mix(bpsSeed) % 5 != 0) return; // arbiter is slow: leaves disputes open for the stale path
        (bool f, uint256 id, uint256 j) = _find(A_RESOLVE, s);
        if (!f) return;
        uint256 k = bpsSeed % 4;
        uint16 bps = k == 0 ? 0 : k == 1 ? 10_000 : uint16(bound(bpsSeed >> 8, 0, 10_000));
        vm.prank(esc.getDeal(id).arbiter);
        esc.resolveDispute(id, j, bps);
        _done(A_RESOLVE, id);
    }

    function resolveStale(uint256 s) external {
        (bool f, uint256 id, uint256 j) = _find(A_STALE, s);
        if (!f) return;
        vm.prank(_anyone(s));
        esc.resolveStaleDispute(id, j);
        _done(A_STALE, id);
    }

    function claimTimeout(uint256 s) external {
        (bool f, uint256 id, uint256 j) = _find(A_CLAIM, s);
        if (!f) return;
        vm.prank(_anyone(s));
        esc.claimAfterTimeout(id, j);
        _done(A_CLAIM, id);
    }

    function refund(uint256 s) external {
        (bool f, uint256 id, uint256 j) = _find(A_REFUND, s);
        if (!f) return;
        vm.prank(_anyone(s));
        esc.refundMilestone(id, j);
        _done(A_REFUND, id);
    }

    function creatorExit(uint256 s) external {
        if (_mix(s) % 8 != 0) return; // creators rarely walk away
        (bool f, uint256 id,) = _find(A_EXIT, s);
        if (!f) return;
        vm.prank(esc.getDeal(id).creator);
        esc.creatorExit(id);
        _done(A_EXIT, id);
    }

    function withdraw(uint256 s) external {
        uint256 len = actors.length;
        for (uint256 t; t < len; ++t) {
            address who = actors[(s % len + t) % len];
            uint256 amt = esc.withdrawable(who);
            if (amt == 0) continue;
            vm.prank(who);
            esc.withdraw();
            totalWithdrawn += amt;
            ok[A_WITHDRAW]++;
            return;
        }
    }

    function warp(uint256 s) external {
        uint256 delta = _mix(s) % 8 == 0 ? bound(s >> 8, 14 days, 20 days) : bound(s >> 8, 1, 30 minutes);
        vm.warp(block.timestamp + delta);
        ok[A_WARP]++;
    }

    /// @dev deterministic warp used only by the reach test (not a fuzz target)
    function warpBy(uint256 delta) external {
        vm.warp(block.timestamp + delta);
        ok[A_WARP]++;
    }

    function setFee(uint256 s) external {
        vm.prank(owner);
        esc.setProtocolFee(uint16(bound(s, 0, 200)));
        ok[A_FEE]++;
    }

    function togglePause(uint256 s) external {
        if (esc.paused()) {
            vm.prank(owner);
            esc.unpause();
            ok[A_PAUSE]++;
        } else if (s % 4 == 0) {
            vm.prank(owner);
            esc.pause();
            ok[A_PAUSE]++;
        }
    }

    // ───────────────────────────── internals ─────────────────────────────

    function _mix(uint256 x) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(x, "mix")));
    }

    function _anyone(uint256 s) internal view returns (address) {
        return actors[(s >> 128) % actors.length];
    }

    function _done(uint256 action, uint256 id) internal {
        ok[action]++;
        PostPaidEscrow.Milestone[] memory ms = esc.getMilestones(id);
        for (uint256 j; j < ms.length; ++j) {
            if (uint8(ms[j].status) >= M_RELEASED && !terminalSeen[id][j]) {
                terminalSeen[id][j] = true;
                terminalHash[id][j] = keccak256(abi.encode(ms[j]));
            }
        }
    }

    function _mask(uint256 id, uint256 j) internal view returns (uint8 m) {
        (bool a, bool b, bool c, bool d, bool e, bool f, bool g,) = esc.milestoneActions(id, j);
        if (a) m |= 1;
        if (b) m |= 2;
        if (c) m |= 4;
        if (d) m |= 8;
        if (e) m |= 16;
        if (f) m |= 32;
        if (g) m |= 64;
    }

    function _elig(uint256 kind, uint256 id, uint256 j, uint8 mstatus) internal view returns (bool) {
        if (kind == A_RESOLVE) return mstatus == M_DISPUTED;
        uint8 m = _mask(id, j);
        if (kind == A_SUBMIT) return m & 1 != 0;
        if (kind == A_APPROVE) return m & 2 != 0;
        if (kind == A_REVISE) return m & 4 != 0;
        if (kind == A_DISPUTE) return m & 8 != 0;
        if (kind == A_CLAIM) return m & 16 != 0;
        if (kind == A_REFUND) return m & 32 != 0;
        if (kind == A_STALE) return m & 64 != 0;
        return false;
    }

    /// @dev Scan up to 12 deals starting at a seeded offset for one where `kind` is currently possible.
    function _find(uint256 kind, uint256 seed) internal view returns (bool, uint256, uint256) {
        uint256 len = dealIds.length;
        if (len == 0) return (false, 0, 0);
        uint256 scan = len < 12 ? len : 12;
        for (uint256 t; t < scan; ++t) {
            uint256 id = dealIds[(seed % len + t) % len];
            PostPaidEscrow.Deal memory d = esc.getDeal(id);
            uint8 ds = uint8(d.status);
            if (ds == D_CANCELLED || ds == D_CLOSED) continue;
            if (kind == A_ACCEPT || kind == A_CANCEL) {
                if (ds == D_OPEN) return (true, id, 0);
                continue;
            }
            PostPaidEscrow.Milestone[] memory ms = esc.getMilestones(id);
            if (kind == A_EXIT) {
                if (ds != D_ACTIVE) continue;
                for (uint256 j; j < ms.length; ++j) {
                    if (uint8(ms[j].status) == M_PENDING) return (true, id, 0);
                }
                continue;
            }
            uint256 off = seed >> 64;
            for (uint256 j; j < ms.length; ++j) {
                uint256 idx = (off + j) % ms.length;
                if (_elig(kind, id, idx, uint8(ms[idx].status))) return (true, id, idx);
            }
        }
        return (false, 0, 0);
    }
}

contract PostPaidEscrowInvariantTest is Test {
    uint256 internal constant T0 = 1_700_000_000;

    MockUSDC internal usdc;
    PostPaidEscrow internal esc;
    PostPaidHandler internal handler;
    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        vm.warp(T0);
        usdc = new MockUSDC();
        esc = new PostPaidEscrow(IERC20(address(usdc)), owner, feeRecipient, 100);
        handler = new PostPaidHandler(esc, usdc, owner, feeRecipient);

        bytes4[] memory sel = new bytes4[](16);
        sel[0] = handler.create.selector;
        sel[1] = handler.accept.selector;
        sel[2] = handler.cancel.selector;
        sel[3] = handler.submit.selector;
        sel[4] = handler.approve.selector;
        sel[5] = handler.revise.selector;
        sel[6] = handler.dispute.selector;
        sel[7] = handler.resolve.selector;
        sel[8] = handler.resolveStale.selector;
        sel[9] = handler.claimTimeout.selector;
        sel[10] = handler.refund.selector;
        sel[11] = handler.creatorExit.selector;
        sel[12] = handler.withdraw.selector;
        sel[13] = handler.warp.selector;
        sel[14] = handler.setFee.selector;
        sel[15] = handler.togglePause.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: sel}));
    }

    // ───────────────────────────── checks (shared with the reach test) ─────────────────────────────

    function _solvency() internal view {
        assertGe(usdc.balanceOf(address(esc)), esc.totalEscrowed() + esc.totalWithdrawable(), "balance < owed");
    }

    function _dealEscrow() internal view {
        for (uint256 i; i < handler.dealCount(); ++i) {
            uint256 id = handler.dealIds(i);
            PostPaidEscrow.Deal memory d = esc.getDeal(id);
            PostPaidEscrow.Milestone[] memory ms = esc.getMilestones(id);
            uint256 live;
            for (uint256 j; j < ms.length; ++j) {
                if (uint8(ms[j].status) < 3) live += ms[j].amount;
            }
            assertEq(d.escrowed, live, "escrowed != non-terminal sum");
            if (d.status == PostPaidEscrow.DealStatus.Cancelled || d.status == PostPaidEscrow.DealStatus.Closed) {
                assertEq(d.escrowed, 0, "finished deal still escrowed");
            }
        }
    }

    function _terminalImmutable() internal view {
        for (uint256 i; i < handler.dealCount(); ++i) {
            uint256 id = handler.dealIds(i);
            PostPaidEscrow.Milestone[] memory ms = esc.getMilestones(id);
            for (uint256 j; j < ms.length; ++j) {
                if (handler.terminalSeen(id, j)) {
                    assertGe(uint8(ms[j].status), 3, "terminal milestone left terminal state");
                    assertEq(keccak256(abi.encode(ms[j])), handler.terminalHash(id, j), "terminal milestone changed");
                } else {
                    assertLt(uint8(ms[j].status), 3, "terminal milestone not snapshotted");
                }
            }
        }
    }

    function _conservation() internal view {
        assertEq(
            handler.totalDeposited(),
            handler.totalWithdrawn() + esc.totalWithdrawable() + esc.totalEscrowed(),
            "deposited != withdrawn + withdrawable + escrowed"
        );
        assertEq(usdc.balanceOf(address(esc)), handler.totalDeposited() - handler.totalWithdrawn(), "balance != net");
    }

    function _sums() internal view {
        uint256 sumEscrowed;
        for (uint256 i; i < handler.dealCount(); ++i) {
            sumEscrowed += esc.getDeal(handler.dealIds(i)).escrowed;
        }
        assertEq(esc.totalEscrowed(), sumEscrowed, "totalEscrowed != sum(deal.escrowed)");
        uint256 sumCredit;
        for (uint256 i; i < handler.actorCount(); ++i) {
            sumCredit += esc.withdrawable(handler.actors(i));
        }
        assertEq(esc.totalWithdrawable(), sumCredit, "totalWithdrawable != sum(withdrawable)");
    }

    function _closedImpliesTerminal() internal view {
        for (uint256 i; i < handler.dealCount(); ++i) {
            uint256 id = handler.dealIds(i);
            PostPaidEscrow.Deal memory d = esc.getDeal(id);
            PostPaidEscrow.Milestone[] memory ms = esc.getMilestones(id);
            bool allTerminal = true;
            for (uint256 j; j < ms.length; ++j) {
                if (uint8(ms[j].status) < 3) allTerminal = false;
            }
            if (d.status == PostPaidEscrow.DealStatus.Closed) assertTrue(allTerminal, "closed with live milestone");
            if (d.status == PostPaidEscrow.DealStatus.Active) assertFalse(allTerminal, "active but all terminal");
        }
    }

    // ───────────────────────────── invariants ─────────────────────────────

    function invariant_BalanceCoversEscrowedAndWithdrawable() public view {
        _solvency();
    }

    function invariant_DealEscrowEqualsNonTerminalMilestones() public view {
        _dealEscrow();
    }

    function invariant_TerminalMilestonesNeverChange() public view {
        _terminalImmutable();
    }

    function invariant_DepositsEqualWithdrawnPlusOwed() public view {
        _conservation();
    }

    function invariant_GlobalTotalsMatchPerAccountAndPerDeal() public view {
        _sums();
    }

    function invariant_ClosedDealHasAllTerminalMilestones() public view {
        _closedImpliesTerminal();
    }

    // ───────────────────────────── reach ─────────────────────────────

    /// @dev Drives the handler with a deterministic pseudo-random sequence and proves every action
    /// is reached with at least one successful call; also re-checks all invariants on the way.
    function test_HandlerReachesEveryAction() public {
        uint256 steps = 2400;
        for (uint256 i; i < steps; ++i) {
            uint256 h = uint256(keccak256(abi.encode("step", i)));
            uint256 s = uint256(keccak256(abi.encode("seed", i)));
            uint256 k = h % 18;
            if (i == 1600 || i == 2200) handler.warpBy(15 days); // forced 14d+ warp (stale disputes, refunds)
            else if (k == 0 || k == 16 || k == 17) handler.create(s, s >> 7, s >> 13, s >> 29);
            else if (k == 1) handler.accept(s);
            else if (k == 2) handler.cancel(s);
            else if (k == 3) handler.submit(s);
            else if (k == 4) handler.approve(s);
            else if (k == 5) handler.revise(s);
            else if (k == 6) handler.dispute(s);
            else if (k == 7) handler.resolve(s, s >> 3);
            else if (k == 8) handler.resolveStale(s);
            else if (k == 9) handler.claimTimeout(s);
            else if (k == 10) handler.refund(s);
            else if (k == 11) handler.creatorExit(s);
            else if (k == 12) handler.withdraw(s);
            else if (k == 13) handler.warpBy(1 + s % 30 minutes); // small warp only
            else if (k == 14) handler.setFee(s);
            else handler.togglePause(s);
            if (i % 500 == 0) this.checkAll();
        }
        this.checkAll();

        string[16] memory names = [
            "create", "accept", "cancel", "submit", "approve", "revise", "dispute", "resolve",
            "resolveStale", "claimTimeout", "refund", "creatorExit", "withdraw", "warp", "setFee", "togglePause"
        ];
        console.log("deals created:", handler.dealCount());
        for (uint256 i; i < handler.NUM_ACTIONS(); ++i) {
            console.log(names[i], handler.ok(i));
            assertGt(handler.ok(i), 0, names[i]);
        }
    }

    /// @dev external so each full scan runs in a fresh memory frame
    function checkAll() external view {
        _solvency();
        _dealEscrow();
        _terminalImmutable();
        _conservation();
        _sums();
        _closedImpliesTerminal();
    }
}
