# PostPaid

USDC escrow for creator campaigns on [Arc](https://www.arc.io/). Brands lock payment up front, creators get paid per milestone, and if the brand goes silent the creator gets paid automatically.

> ⚠️ **Not audited — use small amounts.**

Status: **in development** (see [`PROGRESS.md`](PROGRESS.md)). The full spec is in [`CLAUDE.md`](CLAUDE.md).

<!-- TODO (Phase 7): problem, solution, Mermaid milestone lifecycle, mainnet address, live app,
     how Arc Studio was used, running tests, trust assumptions, roadmap. -->

## Running the app

```bash
bun install --frozen-lockfile
```

```bash
npx vite
```

Configuration lives in `src/postpaid.ts` (defaults to the Arc Testnet deployment); override it with `VITE_CHAIN`, `VITE_ESCROW_ADDRESS` and `VITE_DEPLOY_BLOCK` (see `.env.example`).

UI end-to-end test on an Arc-mode testnet fork: see the header of `scripts/e2e-fork.cjs`.

## Running the contract tests

```bash
bash scripts/setup-sandbox.sh
```

```bash
arc-forge test --network arc
```

Coverage: `arc-forge coverage --report summary`. Optional fork test against real Arc USDC: `ARC_RPC_URL=https://rpc.mainnet.arc.io arc-forge test --mc ArcFork`.

The layout mirrors the Arc Studio workspace: `foundry.toml` at the root, Solidity in `contracts/`, tests in `contracts/test/`.
