# Security review — PostPaidEscrow

> ⚠️ **Not audited — use small amounts.** This is a hackathon build. The review below is our own
> (Arc Studio's built-in review, Slither, and a manual attacker read-through), not a professional audit.

- Contract: `contracts/PostPaidEscrow.sol` (474 lines, solc 0.8.38, `evm_version = osaka`, optimizer 200)
- Tests: 155 passing (unit, fuzz, invariant); 100% line/statement/branch/function coverage. See `docs/ARC_STUDIO_LOG.md`.
- Reviewed: 2026-11-02, at the commit that deployed Arc Testnet `0x4e51c6f82fb8dadd51d650607f05cbb937d3cfe5`.

## §7 checklist

- [x] **Reentrancy.** Only two functions make external calls, and both touch only the immutable USDC: `createDeal` (`safeTransferFrom` plus two `balanceOf`) and `withdraw` (`safeTransfer`). Both are `nonReentrant`. `createDeal` writes all state before pulling funds and checks the balance delta afterwards. `withdraw` zeroes the balance and `totalWithdrawable` before transferring. Every other function makes no external calls at all. Test: `test_Withdraw_ReentrancyIsBlockedAndPaysOnce`.
- [x] **Access control per function.** This matches `test_AccessControl_Table`:

  | Function | Who can call it |
  |---|---|
  | `createDeal` | anyone; the caller becomes the brand; blocked while paused |
  | `cancelDeal`, `approveMilestone`, `requestRevision`, `openDispute` | brand |
  | `acceptDeal`, `submitMilestone`, `creatorExit` | creator |
  | `resolveDispute` | arbiter |
  | `resolveStaleDispute`, `claimAfterTimeout`, `refundMilestone` | anyone; funds go to the fixed parties |
  | `withdraw` | anyone, for their own balance |
  | `setProtocolFee`, `setFeeRecipient`, `pause`, `unpause` | owner |
  | `renounceOwnership` | always reverts |
- [x] **The owner can't take escrowed funds.** No function moves USDC except `withdraw`, which only pays `msg.sender` their own credited balance. The owner can set the fee for **new** deals (capped at 200 bps), change the fee recipient, and pause **new deal creation** only. Note: changing the fee recipient redirects *future* fee credits, including from existing deals. Fees are still capped at each deal's locked bps.
- [x] **Funds can't be stuck.** Every non-terminal state has an exit that needs no cooperation from an absent party:

  | State | Exit |
  |---|---|
  | Deal Open | brand `cancelDeal`. A creator who never accepts can't lock the brand's funds. |
  | Milestone Pending | creator `submitMilestone` (until `dueBy`), or **anyone** `refundMilestone` (after `dueBy`), or creator `creatorExit` |
  | Milestone Submitted | brand `approveMilestone`, or **anyone** `claimAfterTimeout` once the review window ends |
  | Milestone Disputed | arbiter `resolveDispute`, or **anyone** `resolveStaleDispute` after 14 days |
  | Credited balance | owner of the balance calls `withdraw` |

  Exceptions (outside our control): if USDC blocklists an account or Circle pauses USDC, that account's `withdraw` reverts. The credit stays recorded and can be withdrawn once lifted (decision C7). A brand that never cancels an Open deal leaves its *own* funds parked. That's its choice.
- [x] **Timing boundaries don't overlap.** Submit needs `now <= dueBy` and refund needs `now > dueBy`. Review actions need `now < submittedAt + reviewPeriod` and the timeout claim needs `now >= submittedAt + reviewPeriod`. Each pair is exact complements, so at any block timestamp exactly one side is valid. Arc timestamps are non-decreasing (several blocks can share one), which can't create overlap because the checks only compare against the current block's timestamp. Tested at `boundary − 1`, `boundary` and `boundary + 1`, and fuzzed.
- [x] **No `msg.value`, no payable functions, no `receive`/`fallback`.** All accounting uses 6-decimal ERC-20 units. Test: `test_NoEthAccepted`. A grep for `payable|msg.value|tx.origin|unchecked|selfdestruct|delegatecall` finds nothing. Native USDC forced in (e.g. via a `SELFDESTRUCT`, which Arc allows) can only *raise* the balance, so the invariant `balance >= totalEscrowed + totalWithdrawable` still holds. It's never counted as a deposit.
- [x] **Balance-delta check on deposit.** `createDeal` compares `balanceOf` before and after `safeTransferFrom` and reverts with `AmountMismatch` unless the difference is exactly the total. Test: a fee-on-transfer mock. On Arc the ERC-20 view truncates sub-micro-USDC fractions, but a whole-unit transfer always changes the truncated balance by exactly that amount.
- [x] **Loops and strings are bounded.**

  | Item | Bound |
  |---|---|
  | Milestone loops | ≤ 10 (`MAX_MILESTONES`) |
  | Title | 1–80 bytes |
  | Brief | 0–256 bytes |
  | Label | 1–64 bytes |
  | Proof | 1–280 bytes |
  | Revision note, dispute reason | ≤ 280 bytes (approved deviation) |
- [x] **The fee is capped and locked.** `MAX_FEE_BPS = 200` is enforced in the constructor and `setProtocolFee`. Each deal copies `protocolFeeBps` at creation. Fees round down, in the creator's favour. There's no fee on refunds or on the brand's share of a split. Tests: `test_Fees_*` and the rounding cases at 333,333 units.
- [x] **Griefing analysis.**

  | Threat | Outcome |
  |---|---|
  | Brand stalls | Silence for one review period lets anyone call `claimAfterTimeout`; the creator is paid. |
  | Endless revisions | Capped by `maxRevisions` (≤ 3), agreed at creation. Each revision extends `dueBy` to at least `now + reviewPeriod`. **Caveat for the UI:** with a very short review period (e.g. the 10-minute demo preset), the creator also gets only that long to resubmit after a revision request. Show this before the creator accepts. |
  | Creator no-show | Anyone refunds the brand after `dueBy`. |
  | Missing arbiter | After 14 days anyone can split 50/50. |
  | Arbiter collusion | **Trust assumption.** The arbiter can award 0–100% of a disputed milestone. It's opt-in (`address(0)` disables disputes) and named at creation; the UI must show it before the creator accepts. |
  | Racing at a boundary | Brand and creator can race exactly at `reviewEnd` or `dueBy`, but the block timestamp decides deterministically. The brand can always still *approve* after the window, which only helps the creator. |
  | Spam deals | Anyone can create deals naming any creator, which grows `dealsOfCreator`. Each costs the spammer ≥ 0.01 USDC per milestone (recoverable by cancelling) plus gas. Impact is UI clutter only. The app should paginate or filter by status. |
  | Accepting late | A creator may accept a deal whose due dates have passed; those milestones are then immediately refundable. Harmless. |
- [x] **Automated analysis.**
  - **Arc Studio's built-in review** (rule-based and functional) found one **High**: the owner could pause, then renounce ownership, and no new deals could ever be created again. **Fixed**: `renounceOwnership` always reverts.
  - **Slither 0.11.6** (run locally, dependencies and tests excluded) reported 15 results, all triaged:

    | Detector | Verdict |
    |---|---|
    | `divide-before-multiply` (`_split`) | Intended. The spec takes the fee from the creator's gross share. Conservation is fuzz-tested: `creatorNet + fee + brandPart == amount`. |
    | `uninitialized-local` (`refunded`, `d`) | False positive. Zero-initialisation is intended. |
    | `missing-zero-check` (fee recipient) | False positive. The check is in `_validAddress`, which Slither doesn't follow. Tested. |
    | `timestamp` (×8) | Intended. These are the spec's deadline checks, at hour/day scale. |
    | `cyclomatic-complexity` (`_createDeal`) | Accepted. It's validation-heavy by design. |
    | `unindexed-event-address` (`FeeRecipientUpdated`) | Accepted. It's an admin event, rarely queried. |
- [x] **Attacker read-through.** See below.

## Attacker read-through (what we tried)

1. **Double payout of one milestone.** Every payout path (`_release`, `_split`, refund, cancel, exit) first requires a specific non-terminal status, then sets a terminal one before crediting. Terminal states can't be left; the invariant `TerminalMilestonesNeverChange` hashes each terminal milestone and checks it never changes.
2. **Withdraw more than credited.** `withdraw` pays exactly `withdrawable[msg.sender]`, set to 0 first. A second call reverts with `NothingToWithdraw`. A conservation invariant ties the contract's real USDC balance to deposits minus withdrawals.
3. **Act on someone else's deal.** All role checks compare `msg.sender` with addresses stored at creation. There's no `tx.origin` and no signatures, so there's nothing to replay. Unknown deal ids and out-of-range indices revert with `InvalidParams`.
4. **Inflate `escrowed` or the totals.** Totals change only in `_createDeal` (+sum, after validation), `_debit` (−amount on a terminal transition) and `_credit` / `withdraw`. Invariants check that each deal's `escrowed` equals its non-terminal milestones, and the global totals equal the per-deal and per-account sums.
5. **Overflow or underflow.** Solidity 0.8 checks arithmetic. The amount sum checks for overflow explicitly. `uint64` casts take `block.timestamp + reviewPeriod`, which is ≤ 30 days ahead, so they can't overflow in practice.
6. **Move a deadline in my favour.** Only `requestRevision` changes `dueBy`, and only upward (`max`). Only the brand can call it, inside the review window, a capped number of times.
7. **Break things with pause.** `whenNotPaused` appears only on `createDeal`; `test_Pause_OnlyBlocksCreateDeal` exercises every other function while paused.
8. **Malicious token.** USDC is an immutable constructor argument. On Arc it's Circle's `0x3600…0000`, which we verified on-chain on testnet.

## Trust assumptions to disclose (README + app)

- Not audited. Use small amounts.
- Circle's USDC can blocklist accounts or be paused. An affected withdrawal waits until that's lifted.
- An optional arbiter, chosen by both sides, can decide any split of a disputed milestone.
- The owner (`0x553f…CA17`) can change the fee for **new** deals (≤ 2%), change the fee recipient, and pause **new** deal creation. It can never touch escrowed funds.
