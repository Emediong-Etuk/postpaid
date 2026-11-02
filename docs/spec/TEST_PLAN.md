# PostPaidEscrow — test plan (for Arc Studio)

Source: CLAUDE.md §6 and §9 Step C, plus the approved deviations. The contract under test is contracts/PostPaidEscrow.sol (do NOT change its behaviour).

### 6. Test plan (written and run in Arc Studio; also runnable with `arc-forge test`)

Files: `test/mocks/MockUSDC.sol` (6 decimals, mintable), `test/PostPaidEscrow.t.sol`, `test/PostPaidEscrow.invariant.t.sol`, and an optional `test/ArcFork.t.sol`.

**Unit tests — one or more per rule:**
1. **Create:** happy path pulls the exact USDC, stores everything, and emits. Reverts for *each* invalid parameter separately (zero creator, self-deal, arbiter equals a party, 0 or 11 milestones, array length mismatch, amount below the minimum, past due date, review period out of bounds, too many revisions, string too long), when paused, and with insufficient allowance or balance.
2. **Cancel:** brand only, `Open` only, full refund credited and withdrawable. Can't cancel after acceptance.
3. **Accept:** creator only, `Open` only. A cancelled deal can't be accepted.
4. **Submit:** creator only, `Active` only, `Pending` only. Allowed at exactly `dueBy`, reverts at `dueBy + 1`. Proof length bounds enforced.
5. **Approve:** brand only, `Submitted` only. Correct creator/fee credits. Can't approve twice. Works after the review window too.
6. **Revision:** only inside the window. Reverts at exactly `submittedAt + reviewPeriod`. Revision count limit enforced. The due date extends correctly. The creator can resubmit. `maxRevisions = 0` blocks revisions.
7. **Dispute:** reverts without an arbiter, outside the window, or when called by a non-brand. Arbiter resolution at 0, 3333, 5000, and 10000 bps gives exact splits including the fee. Non-arbiter resolution reverts. The stale fallback fails before 14 days and splits 50/50 at exactly 14 days.
8. **Timeout claim:** reverts at `reviewEnd − 1`, works at `reviewEnd`. A random third party can call it and the funds still go to the creator.
9. **Refund:** only `Pending` and only after `dueBy`. Can't refund a Submitted, Disputed, or Released milestone. A third party can call it and the funds still go to the brand.
10. **Creator exit:** refunds only Pending milestones. Submitted ones can still be approved afterwards.
11. **Withdraw:** pays the exact balance and zeroes it. A second call reverts. Several deals credited to the same account add up.
12. **Fees:** changing the fee doesn't affect existing deals. The cap is enforced. Fee rounding is checked with awkward amounts (e.g. 333_333 units at 100 bps).
13. **Close:** the deal auto-closes when the last milestone becomes terminal, through every path.
14. **Pause:** blocks `createDeal` only. Every other function works while paused.
15. **Access control:** a table-driven test where every restricted function is called by each wrong role and must revert.
16. **The demo scenario:** a full end-to-end test of exactly the mainnet demo in §9.

**Fuzz tests:**
- Random amounts and bps: `creatorNet + fee + brandPart == amount` exactly.
- Random timestamps around every boundary.

**Invariant tests** (handler-based: random create, accept, submit, approve, revise, dispute, resolve, claim, refund, exit, withdraw, warp):
- `usdc.balanceOf(escrow) ≥ totalEscrowed + totalWithdrawable`
- Each deal's `escrowed` equals the sum of its non-terminal milestone amounts
- A terminal milestone never changes again
- Total USDC in equals total withdrawn + `totalWithdrawable` + `totalEscrowed`

**Optional fork test** against `https://rpc.mainnet.arc.io`: real USDC at `0x3600…` reports `decimals() == 6`, and our contract deploys against it in a fork.

**Targets:** all tests green, at least 95% line coverage and 90% branch coverage on `PostPaidEscrow.sol`. Paste the coverage summary into `docs/ARC_STUDIO_LOG.md`.

---

#### 6.1 Additional binding details

**Layout (Studio workspace):** `contracts/test/mocks/MockUSDC.sol`, `contracts/test/PostPaidEscrow.t.sol` (unit + fuzz), `contracts/test/PostPaidEscrow.invariant.t.sol` (handler + invariants), `contracts/test/ArcFork.t.sol` (optional fork test). Remove `contracts/test/PostPaidSmoke.t.sol` once the full suite covers it.

**MockUSDC:** ERC-20, `decimals() == 6`, public `mint(address,uint256)`. Add a separate tiny `FeeOnTransferUSDC` mock (takes 1 unit per transfer) only to prove `AmountMismatch`.

**Approved deviations that also need tests:**
- `renounceOwnership()` always reverts (`InvalidParams`), even for the owner; `transferOwnership` + `acceptOwnership` (Ownable2Step) still work.
- `requestRevision` `note` and `openDispute` `reason` > 280 bytes revert `InvalidParams`; exactly 280 is fine.
- Constructor reverts on zero usdc / owner / feeRecipient (`InvalidParams`) and fee > 200 (`FeeTooHigh`); `setFeeRecipient(address(0))` reverts.
- Unknown `dealId` (0 or ≥ nextDealId) and out-of-range milestone index revert `InvalidParams`.

**Exact boundary tests (use `vm.warp`):** submit at `dueBy` ok / `dueBy+1` PastDue; refund at `dueBy` NotYetDue / `dueBy+1` ok; revision & dispute at `reviewEnd-1` ok / `reviewEnd` ReviewWindowClosed; timeout claim at `reviewEnd-1` ReviewWindowOpen / `reviewEnd` ok; stale dispute at `disputedAt+14d-1` DisputeNotStale / `+14d` ok.

**Exact money assertions:** for every release/split/refund assert `withdrawable` of creator, brand and feeRecipient, `deal.escrowed`, `totalEscrowed`, `totalWithdrawable`, and the emitted event args (`vm.expectEmit`). Use fee 100 bps unless a test says otherwise. Split cases on 1_000_000 units: 0, 3333, 5000, 10000 bps; also 333_333 units at 100 bps for rounding.

**`milestoneActions`:** assert every flag and `reviewEndsAt` in each state (Pending before/after due, Submitted inside/after review with and without revisions left / arbiter, Disputed before/after 14 days, terminal states all false). Remember flags are state-only (C1): they ignore the caller.

**Demo scenario test (§6.16) — mirror §9 Step C exactly:** brand A, creator B, no arbiter, review 10 minutes, maxRevisions 1, fee 100 bps, title "PostPaid launch campaign"; milestones "Launch thread" 300_000 due +1 day, "Follow-up thread" 300_000 due +1 day, "Spaces shoutout" 300_000 due +20 minutes. Steps: approve 900_000 → create → accept → submit M1 (tweet URL) → approve M1 → creator withdraw (297_000) → submit M2 → warp 10 min → claimAfterTimeout(M2) → warp past M3 due → refundMilestone(M3) by a third party → creator withdraw (297_000) → brand withdraw (300_000) → feeRecipient withdraw (6_000). Assert balances at each step, deal ends `Closed`, contract USDC balance ends at 0.

**Invariant suite:** handler with bounded actors (3 brands, 3 creators, 2 arbiters, 1 stranger), ghost variables for total deposited and total withdrawn, and a list of created deal ids. Handler actions must bound inputs so most calls succeed (use `bound`, skip invalid states instead of reverting). Invariants: the four in §6, plus "a terminal milestone never changes again" tracked via a ghost snapshot of each milestone's terminal status. Config: `runs = 256`, `depth = 64` (put it in the test via `/// forge-config:` comments or foundry.toml `[invariant]`).

**Fork test:** guard with `vm.envOr("ARC_RPC_URL", string(""))`; if empty, return early (skip). If set, fork it, assert real USDC at 0x3600…0000 has `decimals() == 6`, deploy PostPaidEscrow against it.

**Coverage:** run `forge coverage --report summary` (add `--ir-minimum` only if needed for stack-too-deep). Target ≥ 95% lines and ≥ 90% branches on contracts/PostPaidEscrow.sol. Exclude test/mocks/scripts from the denominator when reporting.
