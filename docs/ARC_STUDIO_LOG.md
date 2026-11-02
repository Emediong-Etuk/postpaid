# Arc Studio log

Every Arc Studio interaction: prompt → what Studio produced → what we changed. Feeds the video and the description.

- **Studio project:** https://studio.arc.io/app/7dce8f44-1629-4058-a90d-748aee960e78
- **Driven from:** Claude Code via Circle's `@circle-fin/arc-studio-cli` (subagent mode, `arc-studio run --output json`), session `postpaid`.
- **Full prompt texts:** `docs/studio-prompts/`

| # | Date | Phase | Prompt | Studio output | Our changes | Screenshot |
|---|---|---|---|---|---|---|
| 1 | 2026-11-02 | 1 — Contract | [`01-contract.txt`](studio-prompts/01-contract.txt) + spec [`PostPaidEscrow.spec.md`](spec/PostPaidEscrow.spec.md) | `contracts/PostPaidEscrow.sol` (474 lines) + `contracts/test/PostPaidSmoke.t.sol` (3 smoke tests); compiled with solc 0.8.38 / osaka / optimizer 200; Studio security review (rule-based + functional) + Slither. Found and fixed 1 High (owner could pause then renounce, which would permanently disable new deals). 5 deviations reported. Trace `01a19b83-cb8d-70ff-8d01-a4cbe398e262`. | None to the code. Line-by-line review against spec: all functions/events/errors/constants/views/C1–C7 match. Local `arc-forge test --network arc`: 3/3 pass. Runtime size 14,438 B. Repo restructured to Studio's layout. | _todo: screenshot of the Studio chat + contract file_ |
| 2 | 2026-11-02 | 2 — Tests | [`02-tests.txt`](studio-prompts/02-tests.txt) + [`TEST_PLAN.md`](spec/TEST_PLAN.md) | `MockUSDC`, `FeeOnTransferUSDC`, `PostPaidEscrow.t.sol` (147 unit+fuzz), `PostPaidEscrow.invariant.t.sol` (7, handler-based), `ArcFork.t.sol` (1); `foundry.toml` gains fuzz 1000 / invariant 256×64. **155/155 green, 100% coverage** on the contract. No contract bugs found; contract untouched. Trace `01a19ce9-5224-757a-a01e-35f751e3796b`. | None. Re-ran locally under Arc rules: 155/155 pass, same coverage; fork test passes against real Arc mainnet USDC. Spot-reviewed the demo test (balances asserted at each step, contract drained to 0) and the invariants (terminal-milestone hash snapshot, conservation vs. real balance). | _todo_ |
| 3 | 2026-11-02 | 3 — Testnet deploy | [`03-testnet-deploy.txt`](studio-prompts/03-testnet-deploy.txt) | Ran tests (green), deployed `PostPaidEscrow` to Arc Testnet at `0x4e51c6f8…cfe5` (tx `0xb762d3b1…bed88`, block 70378581), read back constructor state, wrote `contracts/contract-metadata/PostPaidEscrow.json`. Couldn't set maxFeePerGas itself; landed at 21.1 gwei. Trace `01a19d21-18b7-71b6-8b66-bd1449be86d4`. | Independently re-checked receipt, state and bytecode on-chain. Verified source on testnet Blockscout ourselves (`scripts/verify-blockscout.sh`). | _todo_ |

### #2 — Coverage summary (`arc-forge coverage --report summary`, re-run locally)
| File | % Lines | % Statements | % Branches | % Funcs |
|---|---|---|---|---|
| contracts/PostPaidEscrow.sol | 100.00% (233/233) | 100.00% (318/318) | 100.00% (46/46) | 100.00% (37/37) |

Test run (`arc-forge test --network arc`): 3 suites, 155 passed, 0 failed. Fuzz 1000 runs; invariants 256 runs × depth 64.
Fork test (`ARC_RPC_URL=https://rpc.mainnet.arc.io`): real USDC `decimals() == 6`, escrow deploys against it. Its full deal flow is skipped on the fork because `deal()` can't mint real USDC; the mock-token tests cover that flow.

### #1 — Studio's security review (verbatim summary)
| Source | Finding | Resolution |
|---|---|---|
| Rule-based review | **High:** owner could `pause()` then `renounceOwnership()`, permanently disabling new deals | Fixed: `renounceOwnership()` always reverts |
| Functional review | No material findings | — |
| Slither | Medium `divide-before-multiply` in split math | Accepted: spec-mandated rounding, no dust lost |
| Slither | Medium `uninitialized-local` | False positive (zero-initialised on purpose) |
| Slither | Low/Info: missing-zero-check, timestamp, cyclomatic-complexity, unindexed-event-address | Not actioned (recipient is zero-checked; timestamps are the spec's boundaries; event shape follows spec) |

### #1 — Deviations from spec reported by Studio (approved by Greg 2026-11-02)
1. `renounceOwnership()` disabled (reverts `InvalidParams`).
2. Revision `note` and dispute `reason` capped at 280 bytes (`InvalidParams`).
3. Constructor rejects zero addresses / fee > 200 bps; `setFeeRecipient` rejects zero.
4. `createDeal` takes `memory` instead of `calldata` params (stack too deep); ABI unchanged.
5. 474 lines vs "about 400" (mostly NatSpec).
