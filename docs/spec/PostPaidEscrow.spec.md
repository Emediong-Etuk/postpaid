# PostPaidEscrow — contract specification (for Arc Studio)

Source: CLAUDE.md §5 plus the clarifications Greg accepted on 2026-11-02. Implement exactly this.

### 5. Smart contract specification — `PostPaidEscrow.sol`

#### 5.1 General
- Solidity `^0.8.24`. Use the EVM version that Arc Studio / Arc Foundry defaults to unless the docs say otherwise.
- OpenZeppelin v5: `SafeERC20`, `ReentrancyGuard`, `Ownable2Step`, `Pausable`.
- The USDC address is an `immutable` constructor argument, so tests can use a mock 6-decimal token. On mainnet it's `0x3600…0000`.
- Constructor: `(IERC20 usdc, address initialOwner, address feeRecipient, uint16 initialFeeBps)`.
- **No `payable` functions, no `receive`/`fallback`.**
- **Pull payments only.** Every outflow (to creator, brand, or fee recipient) is credited to `withdrawable[address]` and paid out by `withdraw()`.
- **The owner can never move escrowed funds.** Owner powers are limited to: setting the fee for *new* deals (max 200 bps), setting the fee recipient, and pausing/unpausing **new deal creation only**. Pausing must never block accept, submit, approve, claim, refund, dispute, or withdraw.

#### 5.2 Types
```solidity
enum DealStatus { Open, Active, Cancelled, Closed }
// Open      = funded, waiting for the creator to accept
// Active    = accepted, work in progress
// Cancelled = brand cancelled before acceptance (full refund credited)
// Closed    = every milestone is in a terminal state

enum MilestoneStatus { Pending, Submitted, Disputed, Released, Refunded, Split }
// Terminal states: Released, Refunded, Split

struct Deal {
    address brand;
    address creator;
    address arbiter;        // address(0) = no arbiter; disputes are disabled
    uint64  createdAt;
    uint32  reviewPeriod;   // seconds
    uint16  feeBps;         // locked at creation
    uint8   maxRevisions;   // per milestone, 0..3
    DealStatus status;
    uint256 totalAmount;    // 6-decimal USDC units
    uint256 escrowed;       // amount still locked in non-terminal milestones
    string  title;          // 1..80 bytes
    string  briefURI;       // 0..256 bytes (Notion/Doc/X post with the brief)
}

struct Milestone {
    string  label;          // 1..64 bytes, e.g. "Launch thread"
    uint256 amount;         // >= MIN_MILESTONE
    uint64  dueBy;          // creator must submit by this time
    uint64  submittedAt;
    uint64  disputedAt;
    uint8   revisionsUsed;
    MilestoneStatus status;
    string  proofURI;       // latest proof, 1..280 bytes
}
```

#### 5.3 Constants
- `MIN_MILESTONE = 10_000` (0.01 USDC)
- `MAX_MILESTONES = 10`
- `MIN_REVIEW_PERIOD = 5 minutes` (so the auto-release can be demoed live on mainnet)
- `MAX_REVIEW_PERIOD = 30 days`
- `MAX_REVISIONS = 3`
- `MAX_FEE_BPS = 200`
- `DISPUTE_TIMEOUT = 14 days`
- `BPS = 10_000`

#### 5.4 Functions and rules

**`createDeal(address creator, address arbiter, string title, string briefURI, string[] labels, uint256[] amounts, uint64[] dueBys, uint32 reviewPeriod, uint8 maxRevisions) → uint256 dealId`**
- Rejected when paused. Protected by `nonReentrant`.
- Validation:
  - `creator != 0`, `creator != msg.sender`
  - `arbiter == 0` or (`arbiter != brand` and `arbiter != creator`)
  - `1 ≤ n ≤ 10`, and all three arrays are the same length
  - every `amount ≥ MIN_MILESTONE`, every `dueBy > block.timestamp`
  - `reviewPeriod` within bounds, `maxRevisions ≤ 3`
  - all string lengths within bounds
- Pulls exactly `sum(amounts)` with `safeTransferFrom`. **Checks the balance delta equals the expected total**; reverts with `AmountMismatch` otherwise.
- Locks `feeBps = protocolFeeBps` into the deal. Status becomes `Open`.
- Adds the dealId to `dealsOfBrand[brand]` and `dealsOfCreator[creator]` (and `dealsOfArbiter` if an arbiter is set).
- Emits `DealCreated`.

**`cancelDeal(dealId)`**
- Brand only, while `Open`.
- Credits the full `escrowed` amount to the brand, marks all milestones `Refunded`, sets status `Cancelled`.
- Emits `DealCancelled`.

**`acceptDeal(dealId)`**
- Creator only, while `Open`. Status becomes `Active`.
- Emits `DealAccepted`.

**`submitMilestone(dealId, index, string proofURI)`**
- Creator only. The deal must be `Active` and the milestone `Pending`.
- Must be at or before the due date: `block.timestamp ≤ dueBy`.
- Sets `submittedAt = now`, stores `proofURI`, status becomes `Submitted`.
- Emits `MilestoneSubmitted`.

**`approveMilestone(dealId, index)`**
- Brand only, milestone `Submitted`. Allowed at any time while submitted, even after the review window.
- Releases the payment to the creator (see the fee math in §5.5). Status becomes `Released`.
- Emits `MilestoneReleased(reason = Approved)`.

**`requestRevision(dealId, index, string note)`**
- Brand only, milestone `Submitted`, **inside the review window**: `now < submittedAt + reviewPeriod`.
- Requires `revisionsUsed < maxRevisions`.
- Increments `revisionsUsed` and sets status back to `Pending`.
- Sets `dueBy = max(dueBy, now + reviewPeriod)` so the creator always gets time to resubmit.
- Emits `RevisionRequested(note)`.

**`openDispute(dealId, index, string reason)`**
- Brand only. Requires an arbiter (`arbiter != 0`), milestone `Submitted`, inside the review window.
- Sets `disputedAt = now`, status becomes `Disputed`.
- Emits `DisputeOpened`.

**`resolveDispute(dealId, index, uint16 creatorBps)`**
- Arbiter only, milestone `Disputed`, `creatorBps ≤ 10_000`.
- Splits the payment (§5.5). Status becomes `Split`, or `Released` if `creatorBps == 10_000`, or `Refunded` if `creatorBps == 0`.
- Emits `DisputeResolved`.

**`resolveStaleDispute(dealId, index)`**
- **Anyone** can call. Milestone `Disputed` and `now ≥ disputedAt + DISPUTE_TIMEOUT`.
- Splits 50/50. This exists so funds can never be locked forever by a missing arbiter.

**`claimAfterTimeout(dealId, index)`**
- **Anyone** can call (permissionless, so keepers or the creator can trigger it). Milestone `Submitted` and `now ≥ submittedAt + reviewPeriod`.
- Releases the payment to the creator. Emits `MilestoneReleased(reason = Timeout)`.

**`refundMilestone(dealId, index)`**
- **Anyone** can call; the funds always go to the brand. Deal `Active`, milestone `Pending`, `now > dueBy`.
- Credits the brand. Status becomes `Refunded`. Emits `MilestoneRefunded`.

**`creatorExit(dealId)`**
- Creator only, deal `Active`.
- Every **Pending** milestone becomes `Refunded`, credited to the brand. Submitted and Disputed milestones carry on as normal.
- Emits `CreatorExited`.

**`withdraw()`** (`nonReentrant`)
- Pays `msg.sender` their whole `withdrawable` balance. Zero the balance **before** transferring.
- Reverts with `NothingToWithdraw` if the balance is 0. Emits `Withdrawn`.

**Admin**
- `setProtocolFee(uint16 bps)` (≤ 200; affects new deals only), `setFeeRecipient(address)`, `pause()`, `unpause()`. All `onlyOwner`, all emit events.

**Automatic close:** after any transition into a terminal state, if every milestone in the deal is terminal, set the deal status to `Closed` and emit `DealClosed`.

**Timing boundaries (document these in NatSpec):**
- Submit: `now ≤ dueBy`. Refund: `now > dueBy`. They can never both be valid at the same time.
- Brand review actions: `now < submittedAt + reviewPeriod`. Timeout claim: `now ≥ submittedAt + reviewPeriod`. They can never overlap.

#### 5.5 Money math (all in 6-decimal units, round down, no dust lost)
- **Release to creator:** `fee = amount * feeBps / BPS`, `creatorNet = amount − fee`. Credit `creatorNet` to the creator and `fee` to `feeRecipient`.
- **Split:** `creatorGross = amount * creatorBps / BPS`, `brandPart = amount − creatorGross`, `fee = creatorGross * feeBps / BPS`. Credit the creator `creatorGross − fee`, the fee recipient `fee`, and the brand `brandPart`.
- **Refund:** credit the brand the full amount. No fee on refunds.
- On every terminal transition: `deal.escrowed −= amount`.
- Global accounting:
  - `totalEscrowed` = sum of all `deal.escrowed`
  - `totalWithdrawable` = sum of all `withdrawable`
  - **Invariant:** `usdc.balanceOf(this) ≥ totalEscrowed + totalWithdrawable`

#### 5.6 View functions (designed so the frontend is easy)
- `getDeal(dealId) → Deal`
- `getMilestones(dealId) → Milestone[]`
- `dealsOfBrand(addr)`, `dealsOfCreator(addr)`, `dealsOfArbiter(addr) → uint256[]`
- `withdrawable(addr) → uint256`, `nextDealId()`, `protocolFeeBps()`, `feeRecipient()`
- `milestoneActions(dealId, index) → (bool canSubmit, bool canApprove, bool canRequestRevision, bool canDispute, bool canClaimTimeout, bool canRefund, bool canResolveStale, uint64 reviewEndsAt)`. The UI uses this so it never re-implements the rules.

#### 5.7 Events
`DealCreated(dealId, brand, creator, arbiter, totalAmount, feeBps, reviewPeriod, title, briefURI)`, `DealAccepted`, `DealCancelled`, `DealClosed`, `CreatorExited`, `MilestoneSubmitted(dealId, index, proofURI)`, `RevisionRequested(dealId, index, note, newDueBy)`, `DisputeOpened(dealId, index, reason)`, `DisputeResolved(dealId, index, creatorBps, creatorNet, brandPart, fee)`, `MilestoneReleased(dealId, index, creatorNet, fee, ReleaseReason reason)` (reason = Approved or Timeout), `MilestoneRefunded(dealId, index, amount)`, `Withdrawn(account, amount)`, `ProtocolFeeUpdated`, `FeeRecipientUpdated`. Index `dealId`, `brand`, `creator`, and `account`.

#### 5.8 Custom errors
`NotBrand`, `NotCreator`, `NotArbiter`, `InvalidParams`, `InvalidDealStatus`, `InvalidMilestoneStatus`, `PastDue`, `NotYetDue`, `ReviewWindowClosed`, `ReviewWindowOpen`, `NoRevisionsLeft`, `NoArbiter`, `DisputeNotStale`, `AmountMismatch`, `NothingToWithdraw`, `FeeTooHigh`.

#### 5.9 Code quality
- Full NatSpec on every external function, including who can call it and when.
- Checks-effects-interactions everywhere.
- No `unchecked` blocks unless you prove safety in a comment.
- No `tx.origin`. Loops bounded by `MAX_MILESTONES`.
- Under about 400 lines. Readable beats clever.

---

#### 5.10 Accepted clarifications (binding)
- **C1** `milestoneActions(dealId, index)` takes no caller argument. It returns **state-only** flags (is the action valid right now, ignoring who calls). The UI combines them with the connected wallet's role. `canDispute` also requires `arbiter != address(0)`. `canSubmit`/`canRefund` also require the deal to be `Active`. `reviewEndsAt = submittedAt + reviewPeriod` while Submitted, else 0.
- **C2** `cancelDeal` leaves the deal `Cancelled`. It does **not** emit `DealClosed` and the auto-close rule must not overwrite `Cancelled`. Emit one `DealCancelled(dealId, refundedAmount)`.
- **C3** `resolveStaleDispute` uses the same split path with `creatorBps = 5000` and emits `DisputeResolved(dealId, index, 5000, creatorNet, brandPart, fee)`.
- **C4** `totalEscrowed` and `totalWithdrawable` are `public` state variables, kept up to date on every credit, terminal transition and withdrawal.
- **C5** `creatorExit` reverts with `InvalidMilestoneStatus` if no milestone is Pending.
- **C6** No special handling: after an exit, a revision request may set a milestone back to Pending; it then follows normal submit/refund rules.
- **C7** No "withdraw to another address". A USDC-blocklisted account's balance stays credited (documented trust assumption).
- Storage for `dealsOfBrand/Creator/Arbiter` may be private mappings of `uint256[]` with external view functions of those names that return the whole array.
- Deal ids start at 1 (`nextDealId` starts at 1), so 0 means "no deal".
- Events listed in §5.7 with unspecified params: `DealAccepted(dealId, creator)`, `DealCancelled(dealId, refunded)`, `DealClosed(dealId)`, `CreatorExited(dealId, refunded)`, `ProtocolFeeUpdated(oldBps, newBps)`, `FeeRecipientUpdated(oldRecipient, newRecipient)`.
- If "stack too deep" appears, fix it with internal helpers or structs inside the implementation; do not change the external interface, and avoid `via_ir` unless there's no other way.
- Solidity pragma `^0.8.24`, compiled with solc 0.8.38, `evm_version = osaka` (Arc targets Osaka), optimizer on (200 runs).
