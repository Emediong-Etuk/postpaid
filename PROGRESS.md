# PostPaid — Progress

> New session? Read this file, then `CLAUDE.md` (the full spec). Run `bash scripts/setup-sandbox.sh`
> to rebuild the toolchain, and `export PATH="$HOME/.local/bin:$PATH"`.

## Phase checklist

| Phase | Status |
|---|---|
| 0 — Setup & discovery | ✅ done, waiting for Greg's "go" + answers below |
| 1 — Contract (in Arc Studio) | ⏳ blocked on network allowlist + Studio token |
| 2 — Tests | — |
| 3 — Security & testnet | — |
| 4 — App | — |
| 5 — Mainnet deploy | — |
| 6 — Mainnet demo | — |
| 7 — Ship | — |

## Next action

1. ✅ 2026-11-02: network to arc.io hosts is open, `ARC_STUDIO_TOKEN` is set, and the repo is pushed to https://github.com/Emediong-Etuk/postpaid.
2. Greg: answer the remaining open questions (wallet B, owner wallet, fee, C1–C8 defaults), then say "go".
3. Claude: confirm `arc-studio whoami`, re-verify §4 on docs.arc.io, then start Phase 1 with the first Studio prompt.

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

## Decisions log
- 2026-11-01: `solc 0.8.38`, `evm_version = "prague"` (conservative; Arc supports Osaka). Revisit if Studio's default differs.
- 2026-11-01: libraries are OZ v5.6.1 and forge-std v1.17.0, as submodules.

## Open questions for Greg (see the Phase 0 report in chat)
1. Is the Arc Microgrants window still open? One third-party listing said the deadline was **Oct 15, 2026**.
2. Network allowlist and `ARC_STUDIO_TOKEN` (see the next action).
3. ~~X handle, GitHub, wallet A~~ ✅ received 2026-11-02. Still needed: **wallet B** (creator, must differ from A), **owner/fee-recipient wallet** (default proposal: wallet A), **fee bps** (default proposal: 100).
4. "Pushed from Arc Studio": does the Studio web UI have GitHub export? The CLI has none.
5. Repo layout: mirror Studio's layout (`contracts/` and `src/` at the app root) or keep §10's layout?
6. Contract-spec clarifications (C1–C7 in the chat report).
