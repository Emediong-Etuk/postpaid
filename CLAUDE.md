# PostPaid — Full Build Prompt (Arc Microgrants)

> Source of truth for the build. Progress, decisions, and Phase 0 findings (verified facts that
> refine §4) live in `PROGRESS.md`. **Read PROGRESS.md first in every new session.**

## PROMPT START

### 0. Who you are and what we're doing

You are my senior smart-contract and full-stack engineer and my hackathon co-pilot. We are building **PostPaid** for the **Arc Microgrants** program (Circle's Arc network). I'm Greg: a backend/full-stack developer (PHP/Laravel, Next.js/TypeScript) and a Web3 KOL/ambassador based in Nigeria. I know first-hand the problem this solves.

**Optimise for shipping fast and correctly.** Earlier submissions get reviewed earlier. Simple and solid beats ambitious and broken. Keep the MVP small, test it hard, and ship it, then improve it.

**My details (fill in):**
- X handle: `@gregwrites_yy`
- GitHub username: `Emediong-Etuk` (repo: https://github.com/Emediong-Etuk/postpaid)
- Brand/test wallet A (pays): `0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17`
- Creator/test wallet B (gets paid): `[WALLET_B]` — given `45kASeu3…PMd8` on 2026-11-02, but that is a Solana (base58) address and cannot be used on Arc (EVM). Need a 0x… address that differs from A.
- Fee recipient + contract owner: `0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17` (= wallet A)
- Protocol fee in basis points: `100` (1%)

---

### 1. Eligibility rules — never break these

The hackathon disqualifies projects built outside Arc Studio, testnet-only builds, mockups, and slide decks. Everything we do must satisfy these:

1. **The smart contracts are written and tested in Arc Studio** and deployed to **Arc mainnet** (chain ID 5042).
2. **The app is built in Arc Studio**, calls our contract, and is **live at a public link**.
3. There is **at least one Arc mainnet transaction that moves real USDC through our contract and app**. Use small amounts (under $2 total).
4. **We must be able to produce:** the Arc Studio project URL (looks like `https://studio.arc.io/app/<id>`), the live app link, contract address(es), one example transaction hash with an explorer.arc.io link, a public GitHub repo (pushed from Arc Studio), a video walkthrough showing the build in Arc Studio plus the mainnet transaction, a short description, and my public builder profile.

**So Arc Studio is the home of the build. You (Claude) are the architect, reviewer, test designer, and orchestrator.** Contract code, tests, and the app must be created and iterated *in the Arc Studio project*. If you write code locally, it must also go into Arc Studio and be tested there. Keep a log of every Arc Studio prompt and its result (see §10). That log feeds the video and the description, and judges score "use of Arc Studio across the build" at 25%.

---

### 2. How we're judged, and what we do about each criterion

| Criterion | Weight | Our plan |
|---|---|---|
| Real USDC moving on Arc mainnet, shown with addresses and tx hashes | 30% | A scripted mainnet demo that produces 8+ real USDC transactions (fund, approve, timeout claim, refund, withdrawals), all recorded with explorer links. Ideally also 1–2 small real deals with real KOLs or projects. |
| Use of Arc Studio across contracts, testing, and app | 25% | Contracts, tests, testnet deploy, and the app all happen in Studio. Studio's trace panel is used to debug. Every step is logged and shown in the video. |
| Working product | 25% | A complete flow from both the brand side and the creator side, role-aware UI, clear errors, mobile-friendly. |
| Potential to go further | 20% | A clear roadmap: campaign mode, Circle Wallets onboarding for creators, CCTP/Gateway cross-chain funding, on-chain creator reputation, protocol fee. Documented, **not built**, in the MVP. |

---

### 3. The product

**One-liner:** PostPaid is USDC escrow for creator campaigns. Brands lock payment up front, creators get paid per milestone, and if the brand goes silent the creator gets paid automatically.

**The problem:** Web3 projects hire KOLs and ambassadors for threads, videos, and Spaces. Today either:
- the brand pays first and the creator never delivers, or
- the creator delivers first and the brand ghosts them, pays late, or keeps moving the goalposts.

This is especially painful for creators in emerging markets with no legal recourse.

**The solution:** a single escrow contract with:
- Funds locked at deal creation. The creator can see the money is really there before doing any work.
- Per-milestone release.
- A **review window**: if the brand doesn't respond in time, the creator can claim the payment ("silence = approval").
- A limited number of revision requests, so goalposts can't move forever.
- A **refund** to the brand for milestones the creator never delivered by their due date.
- An **optional arbiter**, agreed by both sides, for disputes, with a deterministic fallback if the arbiter never acts.

**User stories**
- As a **brand**, I create a deal for a creator's wallet with 1–10 milestones, each with an amount, label, and due date. I fund it in USDC in one flow and share a link to the deal.
- As a **creator**, I open the link, see that the USDC is locked and read the terms, then accept.
- As a **creator**, I submit each milestone with a proof link (e.g. a tweet URL).
- As a **brand**, I approve a submission, request a revision (limited), or open a dispute (only if there's an arbiter), all within the review window.
- As a **creator**, if the review window passes with no response, I claim the payment myself.
- As a **brand**, I can reclaim the money for any milestone the creator didn't submit by its due date.
- As a **creator**, I can exit a deal gracefully, which returns all unsubmitted milestones to the brand.
- As **anyone owed money**, I see my withdrawable balance and withdraw it in one click.

---

### 4. Arc network facts (verified Nov 2026 — re-check against docs.arc.io before deploying)

- **Mainnet:** chain ID `5042`, RPC `https://rpc.mainnet.arc.io`, explorer `https://explorer.arc.io`.
- **Testnet:** chain ID `5042002`, RPC `https://rpc.testnet.arc.io`, explorer `https://explorer.testnet.arc.io`, faucet `https://faucet.circle.com`.
- **Gas is paid in USDC.** There is no ETH.
- **USDC ERC-20 interface:** `0x3600000000000000000000000000000000000000`, the same address on mainnet and testnet, **6 decimals**.
- **Native USDC (the gas balance) uses 18 decimals.** It's the same underlying balance as the ERC-20 view. **Our contract never uses `msg.value`.** Every function is non-payable and all accounting uses 6-decimal ERC-20 units moved with `transferFrom`/`transfer`. Never mix `msg.value` with `balanceOf` math.
- **Minimum `maxFeePerGas` is 20 gwei.** Transactions below it are silently dropped. Make sure scripts and the app never go below this.
- `block.timestamp` is **non-decreasing, not strictly increasing** (several blocks can share a timestamp). That's fine for our hour/day-scale deadlines, but document the boundary rules.
- `PREVRANDAO` returns 0. Don't use on-chain randomness.
- **Transfers to or from USDC-blocklisted addresses revert.** That's one reason we use a **pull-payment** design.
- Arc emits `Transfer` logs for native USDC movements too, so the app's timeline must use **PostPaid's own events**, not USDC `Transfer` logs, to avoid double counting.
- **Arc Foundry** (`arc-forge`, `arc-cast`, `arc-anvil`) is Circle's Arc-specific Foundry fork. Releases: `https://github.com/circlefin/arc-foundry/releases`.
- **viem** exports the chains as `arc` (mainnet) and `arcTestnet` from `viem/chains`.
- **Arc Studio** writes Solidity, runs initial reviews, deploys to Arc Testnet in one click, builds a frontend from a deployed contract address (reads and writes wired up, live preview), and has a trace panel (RPC calls, decoded transactions and events). Circle says Studio can also be used as a subagent from Claude Code, Codex, and Cursor. **Arc Studio does not sign, fund, or submit mainnet transactions for you.** I sign mainnet transactions with my own wallet.

**If anything here conflicts with the live docs, the docs win. Tell me what changed.** Never invent addresses, CLI commands, or flags. Look them up or ask me.

---

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

### 7. Security review (do this before *any* mainnet deploy)

Write `docs/SECURITY.md` and go through each item explicitly:
- [ ] Reentrancy: `nonReentrant` on create and withdraw; checks-effects-interactions everywhere; balance zeroed before transfer.
- [ ] Access control verified per function (matches the test table).
- [ ] No path lets the owner (or anyone else) take escrowed funds.
- [ ] Funds can never be permanently stuck. Prove an exit path exists for every state: Open → cancel; Pending → submit or refund; Submitted → approve or timeout; Disputed → resolve or stale fallback.
- [ ] Timing boundaries don't overlap (submit vs refund, review actions vs timeout).
- [ ] No `msg.value`, no payable functions, no native/ERC-20 decimal mixing.
- [ ] The balance-delta check on deposit is in place.
- [ ] Every loop and string is bounded.
- [ ] The fee is capped and locked per deal.
- [ ] Griefing analysis in writing: brand stalling (handled by timeout), endless revisions (capped), creator no-show (refund), arbiter missing (stale fallback), arbiter collusion (a trust assumption, disclosed in the UI before the creator accepts), front-running at boundaries.
- [ ] Run Arc Studio's built-in review. Run Slither too if available. Address or justify every finding.
- [ ] Read the final contract top to bottom as an attacker and write down what you tried.

The hackathon says submissions are not audited. Put a "Not audited — use small amounts" notice in the README and the app footer.

---

### 8. App specification (built in Arc Studio)

**Approach:** after deploying to testnet, give Arc Studio the contract address and ABI and have it generate the frontend. Then iterate *inside Studio* until it matches this spec. If Studio lets me choose the stack, prefer **Next.js (App Router) + TypeScript + wagmi v2 + viem + Tailwind**. If Studio generates something else, keep it as long as it meets the requirements below.

**Config (environment variables):**
- `NEXT_PUBLIC_CHAIN` = `arc` | `arcTestnet` (use the viem chain objects)
- `NEXT_PUBLIC_ESCROW_ADDRESS`, `NEXT_PUBLIC_DEPLOY_BLOCK`
- USDC address as a constant (`0x3600…0000`), 6 decimals
- Explorer base URL per network. Check the exact `/tx/` and `/address/` URL format on explorer.arc.io.

**Pages**
1. **`/` Landing.** One-line pitch, "How it works" in 3 steps (Lock → Deliver → Get paid), two buttons ("Create a deal" and "I'm a creator — view my deals"), and live stats from contract reads (total deals, USDC currently escrowed, if cheap to compute).
2. **`/new` Create deal (brand).**
   - Form: creator wallet, title, brief link, and milestones (add/remove up to 10; each has a label, an amount in USDC, and a due date/time).
   - Review period presets: **10 minutes (demo)**, 24h, 72h (default), 7 days.
   - Max revisions (0–3, default 1) and an optional arbiter address with a short explainer.
   - Summary card: total, fee (from `protocolFeeBps`), and what the creator receives. It also states "You'll sign 2 transactions: Approve USDC → Create deal".
   - Approve the **exact amount**, not an unlimited allowance. Check the existing allowance first and skip the approval if it's already enough.
   - On success, redirect to the deal page with a "Copy link / Share" prompt.
3. **`/deal/[id]` Deal page (role-aware).**
   - Header: title, status pill, brand/creator/arbiter (short addresses, copy buttons), total, amount still escrowed, a link to the brief, and a "Not audited" note.
   - **Open state, creator view:** the terms clearly laid out (review period, revisions, arbiter, fee), with an **Accept deal** button.
   - **Open state, brand view:** a **Cancel & refund** button.
   - **Milestone cards:** label, amount, status, countdown to the due date, countdown to the end of the review window, proof link (tweet links rendered nicely), and *only* the actions `milestoneActions()` allows for the connected wallet's role. Disabled buttons explain why (e.g. "Review window open — auto-release in 1h 42m").
   - **Submit proof modal** for creators (validate that the URL looks like a URL; warn if it isn't an x.com/twitter.com link, but allow it).
   - **Timeline** built from PostPaid events (`getLogs` from the deploy block), each entry with an explorer link.
   - **Share buttons:** copy link, share to X, share to WhatsApp. Many of our users are on mobile.
4. **`/dashboard`.** Tabs: As brand / As creator / As arbiter. The **withdrawable balance** sits prominently at the top with a **Withdraw** button. Deal list with status and next action ("2 milestones awaiting your review").

**UX requirements**
- Wallet connect (injected wallets such as MetaMask/Rabby; add WalletConnect if Studio supports it).
- On the wrong network, prompt to switch or add Arc (chain 5042).
- Show the user's USDC balance (ERC-20, 6 decimals) and note that gas is also paid in USDC. If you show a native balance, format it with 18 decimals and **never** show "ETH".
- Make sure transaction fee settings respect the 20 gwei `maxFeePerGas` minimum.
- Every transaction shows a pending toast, then a confirmed toast with an explorer link. Arc finality is near-instant, so refetch reads right after confirmation.
- Decode custom errors into human messages (e.g. `ReviewWindowOpen` → "You can claim after the review window ends").
- Mobile-first layout, loading skeletons, empty states, no console errors.
- No backend, no private keys, no secrets in the frontend.

**Hosting:** use Arc Studio's hosting/preview if it gives a stable public URL. Otherwise push to GitHub from Studio and deploy on Vercel with the env vars above. The live link must work in a fresh browser.

---

### 9. Deployment and the mainnet demo

**Step A — testnet rehearsal (required before mainnet).**
1. Deploy to Arc Testnet from Arc Studio (one click). Get testnet USDC from faucet.circle.com for both wallets.
2. Run the *entire* demo script below on testnet through the app. Fix everything. Use Studio's trace panel to debug failures and log what you found.

**Step B — mainnet deploy (I sign).**
- **Preferred:** deploy from Arc Studio to Arc mainnet with my wallet signing, if Studio supports that. This keeps the deploy visibly inside Studio for the video.
- **Fallback:** Arc Foundry with an **encrypted keystore**. Never put a raw private key in a file, a command, or this chat. Give me the exact commands to run myself, checked against the Arc Foundry docs: keystore import, then a `Deploy.s.sol` broadcast to `https://rpc.mainnet.arc.io` (chain 5042), with gas at least 20 gwei.
- **Constructor:** USDC `0x3600000000000000000000000000000000000000`, owner `[OWNER_WALLET]`, fee recipient `[OWNER_WALLET]`, fee `[FEE_BPS]`.
- **Verify the contract source** on explorer.arc.io. Find the official method in the docs; don't guess.
- Record the address, deploy transaction, and deploy block in `docs/TRANSACTIONS.md`. Then point the app at mainnet.

**Step C — mainnet demo script** (about 1 USDC moved; fund wallet A with about 2 USDC and wallet B with about 0.3 USDC for gas)

Deal: **"PostPaid launch campaign"**, 3 milestones × **0.30 USDC**, review period **10 minutes**, max revisions 1, no arbiter.
- M1 "Launch thread": due in 1 day
- M2 "Follow-up thread": due in 1 day
- M3 "Spaces shoutout": due in **20 minutes** (so we can demo a refund)

| # | Actor | Action | What it proves |
|---|---|---|---|
| 1 | Brand (A) | Approve 0.90 USDC | Allowance |
| 2 | Brand (A) | Create deal | **USDC moves into escrow** |
| 3 | Creator (B) | Accept deal | Consent |
| 4 | Creator (B) | Submit M1 with a real tweet URL | Proof on-chain |
| 5 | Brand (A) | Approve M1 | Release |
| 6 | Creator (B) | **Withdraw** | **USDC moves out to the creator ← main submission tx** |
| 7 | Creator (B) | Submit M2, wait 10 minutes, then `claimAfterTimeout` | "Silence = approval" |
| 8 | Anyone | After M3's due date passes, `refundMilestone(M3)` | Brand protection |
| 9 | Creator (B) / Brand (A) | Withdraw again | More real USDC movement |

Log every transaction hash with its explorer link in `docs/TRANSACTIONS.md`. **Bonus (strong signal):** I'll ask 1–2 real projects or KOLs from my network to run a small real deal ($1–5). Add those transactions too.

---

### 10. Repo, docs, and the submission pack

**Repo layout** (pushed to public GitHub from Arc Studio):
```
postpaid/
├── contracts/            # Foundry / Arc Foundry project
│   ├── src/PostPaidEscrow.sol
│   ├── test/ (unit, fuzz, invariant, mocks, fork)
│   ├── script/Deploy.s.sol
│   └── foundry.toml
├── app/                  # Arc Studio-generated frontend
├── docs/
│   ├── ARC_STUDIO_LOG.md     # every Studio prompt → result → screenshot placeholder
│   ├── SECURITY.md
│   ├── TRANSACTIONS.md       # mainnet addresses + all tx hashes with explorer links
│   ├── DEMO_SCRIPT.md
│   ├── VIDEO_SCRIPT.md
│   └── SUBMISSION.md
├── PROGRESS.md           # phase checklist + decisions + next step (keep updated)
└── README.md
```

**README.md:** problem, solution, a Mermaid state diagram of the milestone lifecycle, mainnet contract address with explorer link, live app link, how Arc Studio was used (contracts, tests, review, testnet deploy, app builder, trace panel), how to run tests, trust assumptions, a "Not audited" notice, and the roadmap.

**docs/SUBMISSION.md** — ready to copy into the form:
- Arc Studio project URL: `https://studio.arc.io/app/…` (get it from the browser address bar or the Arc Studio CLI)
- Live app: …
- Contract: `0x…`, with an explorer.arc.io link
- Example transaction: the creator **Withdraw** tx hash, with its explorer link (plus the createDeal tx)
- Repo: `https://github.com/Emediong-Etuk/postpaid`
- Video: …
- Builder profile: `https://x.com/gregwrites_yy`
- Description (≤ 150 words): what PostPaid does, plus one sentence each on how Arc Studio was used for contracts, testing, and the app.

**docs/VIDEO_SCRIPT.md** — a 3–4 minute walkthrough:
1. The problem (15s)
2. Arc Studio: the prompt that generated the contract, plus Studio's review (40s)
3. Tests running green in Studio, with coverage (25s)
4. Testnet deploy and the trace panel (20s)
5. The app builder in Studio (20s)
6. Mainnet flow from both wallets: create → accept → submit → approve → withdraw (60s)
7. The timeout claim and the refund (30s)
8. Explorer pages showing USDC moving (15s)
9. Roadmap (15s)

---

### 11. Phases — STOP and wait for my "go" after each one

Keep `PROGRESS.md` updated at the end of every phase. I'm on Claude Pro usage limits, so work in focused phases, don't repeat work, and make sure any new session can pick up from `PROGRESS.md`.

- **Phase 0 — Setup and discovery.** Mode A/B; how to drive Arc Studio from here; check tools; re-verify §4; repo skeleton + `PROGRESS.md`; list ambiguities. **STOP.**
- **Phase 1 — Contract.** Generate `PostPaidEscrow.sol` in Arc Studio from §5, review it line by line against the spec, and fix gaps. Show me a summary of deviations, if any. **STOP.**
- **Phase 2 — Tests.** Build the full §6 suite in Studio until everything is green, with coverage at target. **STOP.**
- **Phase 3 — Security and testnet.** Complete §7, deploy to Arc Testnet from Studio, and run the demo flow with scripts or `arc-cast`. **STOP.**
- **Phase 4 — App.** Build the app in Arc Studio against the testnet contract, meet every requirement in §8, and click through the full flow with both wallets. **STOP.**
- **Phase 5 — Mainnet.** Prepare the mainnet deploy (I sign), verify the source, switch the app to mainnet, and get a public URL. **STOP.**
- **Phase 6 — Mainnet demo.** Walk me through §9 Step C one transaction at a time and record every hash. **STOP.**
- **Phase 7 — Ship.** Push the repo from Studio, finish the README and all docs, draft the description and video script, and run the final checklist below. **STOP.**

**Final pre-submission checklist**
- [ ] Arc Studio project URL works and shows the contracts, tests, and app
- [ ] Contract deployed on mainnet (5042) and source verified
- [ ] Live app loads in a fresh browser, connects a wallet, and runs the full flow on mainnet
- [ ] At least one mainnet transaction moved USDC through the contract; hashes and explorer links recorded
- [ ] Repo is public and pushed from Arc Studio; README complete; no secrets committed (`.env` in `.gitignore`)
- [ ] Video recorded, showing the Studio build and the mainnet transaction
- [ ] Description and builder profile ready; `SUBMISSION.md` complete

---

### 12. Working rules for you

1. **Never** ask for, print, store, or commit private keys or seed phrases. Use keystores or browser wallets. I run anything that signs a mainnet transaction.
2. Never invent addresses, CLI commands, flags, or Arc Studio features. Verify them in the docs, or say "I'm not sure" and ask me.
3. Keep the MVP scope exactly as specified. If you think something should change, propose it with one line of reasoning and wait for my answer.
4. Small amounts only on mainnet. Double-check the 6-decimal conversion (`parseUnits(x, 6)`) before every transaction we prepare.
5. After each phase, give me: what was done, what's left, any risks, and the exact next action. Be concise; no long recaps.
6. Log every Arc Studio interaction in `docs/ARC_STUDIO_LOG.md` (prompt → what Studio produced → what we changed).
7. When something fails, check Studio's trace panel or the transaction receipt before guessing.
8. Write clean, commented code a judge can read quickly.

---

### 13. Roadmap (document in the README; do NOT build before submitting)
- **Campaign mode:** one brand, many creators, a shared budget, per-creator milestones.
- **Circle Wallets:** email/social login so creators without crypto wallets can get paid.
- **CCTP / Gateway:** brands fund deals with USDC from Base, Ethereum, or Solana.
- **On-chain creator reputation:** completed deals, on-time rate, dispute rate.
- **Automatic proof verification:** an agent checks the tweet exists, then auto-approves.
- **Off-ramp partners** for local-currency payouts (e.g. NGN).
- **Business model:** a 1% protocol fee on released payouts, already in the contract.

## PROMPT END
