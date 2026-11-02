# PostPaid app — specification (for Arc Studio)

Source: CLAUDE.md §8, adapted to this workspace's stack (Vite + React + TypeScript + wagmi v2 + viem + Tailwind), plus UI requirements from docs/SECURITY.md. Keep the existing stack; do not migrate to Next.js.

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

#### 8.1 Binding adaptations for this workspace

**Contract.** `PostPaidEscrow` on **Arc Testnet** (chain 5042002):
- address `0x4e51c6f82fb8dadd51d650607f05cbb937d3cfe5`, deploy block `70378581`, source verified on explorer.testnet.arc.io
- ABI: use `contracts/contract-metadata/PostPaidEscrow.json` (or the forge artifact). **Do not redeploy or change the contract.**
- Owner and fee recipient `0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17`, fee 100 bps (read `protocolFeeBps()`; never hard-code it).

**Config (Vite env, all with safe defaults in one file, e.g. `src/postpaid.ts`):**
- `VITE_CHAIN` = `arcTestnet` (default) | `arc`. Use viem's `arcTestnet` / `arc` chain objects from `viem/chains`.
- `VITE_ESCROW_ADDRESS` (default: testnet address above), `VITE_DEPLOY_BLOCK` (default `70378581`).
- USDC = `0x3600000000000000000000000000000000000000`, **6 decimals** (use `parseUnits(x, 6)` / `formatUnits(x, 6)` for every amount).
- Explorer base: `https://explorer.testnet.arc.io` (testnet) / `https://explorer.arc.io` (mainnet). Links are `${base}/tx/${hash}` and `${base}/address/${addr}`.
- Switching to mainnet later must only require changing the env vars (Phase 5).

**Routing.** Clean URLs: `/`, `/new`, `/deal/:id`, `/dashboard` (react-router or equivalent). Because this is a static SPA, also add host fallbacks so deep links work in a fresh browser: `vercel.json` (rewrite all to `/index.html`) and `public/_redirects` (`/* /index.html 200`) for Netlify.

**Gas.** Arc's mempool silently drops `maxFeePerGas < 20 gwei`. For every write, set `maxFeePerGas = max(estimate, 25 gwei)` and `maxPriorityFeePerGas ≥ 1 gwei` (e.g. via `estimateFeesPerGas` then clamp). Gas is paid in USDC; never show "ETH".

**Wallets.** Injected wallets (MetaMask / Rabby) are enough; skip WalletConnect unless it works without a secret. On the wrong chain, offer `switchChain` and, if the wallet lacks Arc, `addChain` with the viem chain object.

**Reads.** Use `getDeal`, `getMilestones`, `milestoneActions`, `withdrawable`, `dealsOfBrand/Creator/Arbiter`, `nextDealId`, `totalEscrowed`, `protocolFeeBps`. `milestoneActions` flags are **state-only** — combine with the connected wallet's role (brand / creator / arbiter / anyone) to decide which buttons to show:
- creator: submit (canSubmit), exit deal (Active + any Pending)
- brand: approve (canApprove), request revision (canRequestRevision), open dispute (canDispute), cancel (deal Open)
- arbiter: resolve dispute (Disputed) with a 0–100% slider
- anyone (incl. creator/brand): claim after timeout (canClaimTimeout), refund (canRefund), resolve stale dispute (canResolveStale)
Enum orders: DealStatus {Open, Active, Cancelled, Closed}; MilestoneStatus {Pending, Submitted, Disputed, Released, Refunded, Split}.

**Timeline.** `getLogs` for PostPaid's own events only (never USDC Transfer logs — Arc also emits native Transfer logs from a system address) from `VITE_DEPLOY_BLOCK`, filtered by `dealId` topic, in chunks of ≤ 10,000 blocks; show each with time and explorer link.

**Error decoding.** Decode custom errors with the ABI and map to plain English:
NotBrand "Only the brand can do this" · NotCreator "Only the creator can do this" · NotArbiter "Only the arbiter can do this" · InvalidParams "Some inputs are invalid (check addresses, amounts, dates and text lengths)" · InvalidDealStatus "The deal isn't in the right state for this" · InvalidMilestoneStatus "This milestone isn't in the right state for this" · PastDue "The due date has passed" · NotYetDue "You can refund after the due date passes" · ReviewWindowClosed "The review window has closed" · ReviewWindowOpen "You can claim after the review window ends" · NoRevisionsLeft "No revisions left for this milestone" · NoArbiter "This deal has no arbiter" · DisputeNotStale "The arbiter still has time to decide (14 days)" · AmountMismatch "The USDC amount received didn't match" · NothingToWithdraw "Nothing to withdraw yet" · FeeTooHigh "Fee too high" · EnforcedPause "New deals are paused right now". Also handle user-rejected signatures quietly and insufficient USDC / allowance with clear text.

**Create-deal validation (client-side, mirror the contract):** creator ≠ 0 and ≠ connected wallet; arbiter empty or ≠ brand/creator; 1–10 milestones; each amount ≥ 0.01 USDC; each due date in the future; title 1–80 bytes; brief ≤ 256 bytes; labels 1–64 bytes; proof 1–280 bytes; revision note / dispute reason ≤ 280 bytes. Check the brand's USDC balance before asking for signatures. Approve the **exact** total only if `allowance < total`.

**Disclosures from the security review (must appear):**
- Footer on every page: "Not audited — use small amounts."
- On the creator's Accept screen: the review period, max revisions, fee, and — if the review period is short (< 1 hour) — a warning that after a revision request the creator gets at least one review period to resubmit (e.g. only 10 minutes on the demo preset).
- If an arbiter is set: "The arbiter can decide any split of a disputed milestone. Only accept if you trust them." Shown before Accept.
- Dashboard: filter deals by status (Active / Open / Closed / Cancelled) so spam deals don't clutter the view.

**Look & feel.** Clean, mobile-first, high contrast, works at 360 px wide; loading skeletons; empty states; toasts (pending → confirmed with explorer link); no console errors. Brand name "PostPaid", tagline "Get paid for every post. Guaranteed." (you may refine wording).
