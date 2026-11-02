# Arc Studio log

Every Arc Studio interaction: prompt → what Studio produced → what we changed. Feeds the video and the description.

- **Studio project:** https://studio.arc.io/app/7dce8f44-1629-4058-a90d-748aee960e78
- **Driven from:** Claude Code via Circle's `@circle-fin/arc-studio-cli` (subagent mode, `arc-studio run --output json`), session `postpaid`.
- **Full prompt texts:** `docs/studio-prompts/`

| # | Date | Phase | Prompt | Studio output | Our changes | Screenshot |
|---|---|---|---|---|---|---|
| 1 | 2026-11-02 | 1 — Contract | [`01-contract.txt`](studio-prompts/01-contract.txt) + spec [`PostPaidEscrow.spec.md`](spec/PostPaidEscrow.spec.md) | `contracts/PostPaidEscrow.sol` (474 lines) + `contracts/test/PostPaidSmoke.t.sol` (3 smoke tests); compiled with solc 0.8.38 / osaka / optimizer 200; Studio security review (rule-based + functional) + Slither. Found and fixed 1 High (owner could pause then renounce, which would permanently disable new deals). 5 deviations reported. Trace `01a19b83-cb8d-70ff-8d01-a4cbe398e262`. | None to the code. Line-by-line review against spec: all functions/events/errors/constants/views/C1–C7 match. Local `arc-forge test --network arc`: 3/3 pass. Runtime size 14,438 B. Repo restructured to Studio's layout. | _todo: screenshot of the Studio chat + contract file_ |

### #1 — Studio's security review (verbatim summary)
| Source | Finding | Resolution |
|---|---|---|
| Rule-based review | **High:** owner could `pause()` then `renounceOwnership()`, permanently disabling new deals | Fixed: `renounceOwnership()` always reverts |
| Functional review | No material findings | — |
| Slither | Medium `divide-before-multiply` in split math | Accepted: spec-mandated rounding, no dust lost |
| Slither | Medium `uninitialized-local` | False positive (zero-initialised on purpose) |
| Slither | Low/Info: missing-zero-check, timestamp, cyclomatic-complexity, unindexed-event-address | Not actioned (recipient is zero-checked; timestamps are the spec's boundaries; event shape follows spec) |

### #1 — Deviations from spec reported by Studio (pending Greg's OK)
1. `renounceOwnership()` disabled (reverts `InvalidParams`).
2. Revision `note` and dispute `reason` capped at 280 bytes (`InvalidParams`).
3. Constructor rejects zero addresses / fee > 200 bps; `setFeeRecipient` rejects zero.
4. `createDeal` takes `memory` instead of `calldata` params (stack too deep); ABI unchanged.
5. 474 lines vs "about 400" (mostly NatSpec).
