# PostPaid — Progress

> New session? Read this file, then `CLAUDE.md` (the full spec). Run `bash scripts/setup-sandbox.sh`
> to rebuild the toolchain, and `export PATH="$HOME/.local/bin:$PATH"`.

## Phase checklist

| Phase | Status |
|---|---|
| 0 — Setup & discovery | ✅ done |
| 1 — Contract (in Arc Studio) | ✅ done: waiting for Greg's OK on 5 small deviations + "go" |
| 2 — Tests | — |
| 3 — Security & testnet | — |
| 4 — App | — |
| 5 — Mainnet deploy | — |
| 6 — Mainnet demo | — |
| 7 — Ship | — |

## Next action

1. Greg: approve the 5 deviations in `docs/ARC_STUDIO_LOG.md` (#1) and say "go" for Phase 2.
2. Claude (Phase 2): send Studio the §6 test plan (unit + fuzz + invariant + MockUSDC), pull it back, run `arc-forge test --network arc` + coverage locally, iterate in Studio until green with ≥95% line / ≥90% branch coverage.
3. Still needed from Greg before Phase 3: an **EVM wallet B** (0x…).

## Mode

**Mode A (with limits).** Claude Code on the web: a remote Linux sandbox that can run commands, but it is not Greg's machine. It cannot open a browser, hold a wallet, or sign anything. Greg signs every mainnet transaction on his own device. The container is ephemeral, so work must be committed and pushed.

## Phase 0 findings

### Toolchain (installed in the sandbox; `scripts/setup-sandbox.sh` reproduces it)
- Node v22.23.4, npm 10.9.9, git 2.43.0, Rust/cargo present.
- **Arc Foundry v0.8.0-2** (forge 1.7.1-dev, commit d497bee), from GitHub releases. SHA-256 verified.
- **solc 0.8.38**, static binary from the Solidity GitHub release. SHA-256 matches solc-bin `list.json`. (`binaries.soliditylang.org` is blocked here, so forge can't auto-download solc; it's pinned in `foundry.toml`.)
- forge-std v1.17.0 and **OpenZeppelin Contracts v5.6.1** as git submodules in `contracts/lib/`.
- `FOUNDRY_PROFILE=arc arc-forge config` resolves `"network": "arc"`, so Arc execution mode works.
- Caveat: the v0.8.0-2 release does **not** seed the USDC predeploy at `0x3600…` in local Arc mode (a call there hits a "non-contract address" error). Seeding exists on Arc Foundry `master` (Oct 30) but isn't released yet. Unit tests use `MockUSDC` per spec anyway; real-USDC checks go in the fork test.
- Arc Studio CLI **`@circle-fin/arc-studio-cli@1.2.2`** installed. `arc-studio whoami` currently reports "Not authenticated".

### How we drive Arc Studio from here (confirmed integration)
Circle publishes `@circle-fin/arc-studio-cli` (npm, maintained by Circle staff). Read from its packaged README and agent guide:
- `arc-studio run "<task>" --session <name> --output json`: runs a turn in Studio's hosted sandbox and returns JSON (`fileDiffs`, `deployments[]`, `webUrl`, …). `--file local:contracts/X.sol` round-trips a file; `--detach` / `arc-studio attach` handle long turns.
- `arc-studio pull --session <name> --out <dir> --paths "contracts/**"` brings Studio's files back here.
- `arc-studio deployments --json`, `apps --json`, `open`, `usage --json`.
- Auth for a sandbox: env var **`ARC_STUDIO_TOKEN`**. Greg gets it from `arc-studio login --paste` (which opens the authorize page) on his own machine. Never paste it in chat.
- App URL format: `https://studio.arc.io/app/<appId>`, confirmed in the CLI source.
- **Studio's sandbox is a Vite + Foundry app**: Solidity under `contracts/`, web code under `src/`. It is not Next.js.
- Studio deploys to **Arc testnet by default**. The CLI has no mainnet signing and **no GitHub push command** (only `clone` for public repos).
- Fallback if the CLI stays blocked: Claude writes prompts, Greg pastes them into studio.arc.io, then runs `arc-studio pull` locally or pastes the results back.

### §4 re-verification
docs.arc.io, developers.circle.com and studio.arc.io are **blocked** from this sandbox, so §4 was checked against Circle's own source code instead (arc-node, arc-foundry) and viem 2.57.14:

| Fact | Result | Source |
|---|---|---|
| Mainnet chain ID 5042 | ✅ | arc-node `assets/mainnet/genesis.config.ts`; viem `arc` |
| Testnet chain ID 5042002 | ✅ | arc-node testnet genesis; viem `arcTestnet` |
| RPC `rpc.mainnet.arc.io` / `rpc.testnet.arc.io` | ✅ (plus Blockdaemon, dRPC, QuickNode mirrors) | viem |
| Explorers `explorer.arc.io` / `explorer.testnet.arc.io` | ✅ API at `explorer.arc.io/api/v2`, so it's Blockscout-style | viem |
| USDC `0x3600…0000`, 6 decimals, symbol USDC | ✅ | arc-node genesis `NativeFiatToken.ts` storage slots |
| Native USDC 18 decimals | ✅ | viem `nativeCurrency` |
| Min base fee 20 gwei | ✅ on mainnet (`minBaseFee: parseGwei('20')`, max 20,000 gwei) | arc-node genesis |
| Timestamps non-decreasing | ✅ | arc-node ADR-0006 |
| Blocklist reverts transfers | ✅ (mainnet denylist contract `0x3600…0004`) | arc-node chainspec; arc-foundry tests |
| Ethereum forks through Osaka active at genesis | ✅ | mainnet `genesis.json` |
| Target block time 500 ms | info | mainnet ProtocolConfig |
| PREVRANDAO = 0; native `Transfer` logs | ⚠️ not verified yet | needs docs.arc.io |
| Faucet URL; contract verification method | ⚠️ not verified yet | needs docs |

Nothing contradicts §4 so far.

## Arc Studio project
- App URL: https://studio.arc.io/app/7dce8f44-1629-4058-a90d-748aee960e78
- CLI session name: `postpaid`. Always call the CLI through `scripts/studio.sh`: it sets `NODE_USE_ENV_PROXY=1` and the sandbox CA bundle. Without them the CLI wrongly reports "token rejected", because Node's fetch ignores the proxy.
- Plan: free. Prompts sent are kept in `docs/studio-prompts/`.

## §4 re-verified on docs.arc.io (2026-11-02)
Every §4 fact is confirmed by docs.arc.io (`arc/references/evm-differences.md`, `connect-to-arc.md`), including PREVRANDAO = 0, the 20 gwei `maxFeePerGas` floor (lower is silently dropped), non-decreasing timestamps, and the blocklist.
New details:
- **Arc targets the Osaka EVM** → `evm_version = "osaka"` (was prague).
- Native USDC `Transfer` logs (EIP-7708) come from the system emitter `0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE`, so the app timeline must use PostPaid's own events.
- A value transfer to `address(0)` reverts. A blocklist revert still consumes gas.
- **Contract verification:** Blockscout, via `arc-forge verify-contract <addr> src/X.sol:X --chain-id <id> --verifier blockscout --verifier-url https://explorer.testnet.arc.io/api/` (testnet example from `build/deploy-on-arc.md`; mainnet presumably `https://explorer.arc.io/api/`, to confirm in Phase 5).

## Repo layout (mirrors the Arc Studio workspace, decision C8)
- `foundry.toml` + `remappings.txt` at the root (copied from Studio): `src = "contracts"`, tests in `contracts/test/`, out/cache under `contracts/`.
- OpenZeppelin 5.6.1 comes from `node_modules/` (npm), as in Studio. forge-std is a submodule in `lib/`.
- Run tests with `arc-forge test --network arc`. That flag switches to Arc rules without editing Studio's `foundry.toml`.
- Studio's own files (`package.json`, `src/` Vite app, `scripts/`) get pulled in Phase 4.
- Studio's app template: Vite + React + wagmi + viem 2.57.5 + ConnectKit + Tailwind. It can deploy to **Vercel or Netlify** through its Integrations menu, which answers §8 hosting.

## Decisions log
- 2026-11-01: `solc 0.8.38`, `evm_version = "prague"`.
- 2026-11-02: switched to `evm_version = "osaka"`: docs say Arc targets Osaka, and Arc Foundry defaults to it.
- 2026-11-02: Phase 1 contract generated in Studio (turn #1); local copy is byte-identical to Studio's.
- 2026-11-01: libraries are OZ v5.6.1 and forge-std v1.17.0, as submodules.

## Answers received (2026-11-02)
- Microgrants: **still accepting submissions** (Greg confirmed).
- Owner + fee recipient: **wallet A** `0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17`. Fee: **100 bps**.
- C1–C8 spec clarifications: **defaults accepted**:
  - C1 `milestoneActions` returns state-only flags; the UI combines them with the wallet's role.
  - C2 a cancelled deal stays `Cancelled` and emits no `DealClosed`.
  - C3 `resolveStaleDispute` emits `DisputeResolved(creatorBps = 5000)`.
  - C4 `totalEscrowed` and `totalWithdrawable` are public.
  - C5 `creatorExit` reverts when no milestone is Pending.
  - C6 after an exit, a revision request makes the milestone refundable after its due date (no change).
  - C7 a blocklisted account's balance can stay stuck (no withdraw-to-another-address); disclosed as a trust assumption.
  - C8 the repo mirrors Studio's layout (`contracts/` + `src/` at the root), with `VITE_*` env vars instead of `NEXT_PUBLIC_*`.
- Wallet B: Greg sent `45kASeu3EqH3qRzHkEwk8pNQwkEeQVtR34NEeET4PMd8`, which is a **Solana address**. Still need an EVM 0x… address.

## Open questions for Greg (see the Phase 0 report in chat)
1. ~~Microgrants still open?~~ ✅ yes.
2. `ARC_STUDIO_TOKEN` is rejected; needs a fresh token.
3. ~~X, GitHub, wallet A, owner, fee~~ ✅. Still needed: **EVM wallet B**.
4. "Pushed from Arc Studio": does the Studio web UI have GitHub export? The CLI has none.
5. ~~Repo layout~~ ✅ mirror Studio (C8).
6. ~~Contract-spec clarifications~~ ✅ defaults accepted.
