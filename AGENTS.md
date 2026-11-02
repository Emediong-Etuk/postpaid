# [App Name]

> Built with Arc Studio - money-powered apps in minutes

This is the **project memory** - what Arc Studio remembers about building this app. It helps future agents (or humans) understand and extend the project.

---

## What This App Does

[Brief description of what the app does and its primary use case]

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry. Sources in `contracts/`, unit tests in `contracts/test/*.t.sol`. Build with `bun run contracts:build` (`forge build`), test with `bun run contracts:test` (`forge test`).
- Wallet: injected (MetaMask, etc.)
- Chain: Arc Testnet (Chain ID: 5042002, imported from `viem/chains`)
- Token: USDC (6 decimals) (Address: 0x3600000000000000000000000000000000000000, Chain: Arc Testnet)
- Toasts: Sonner

## Key Files

- `src/App.tsx` - Main application logic
- `src/components/` - UI components
- `src/config.ts` - wagmi config (chains, connectors, transports)

## Share links

- Starter apps already ship `getShareBase`, `buildShareLink` and `installShareSync` in `src/lib/share.ts`; import them instead of rewriting them.
- Keep shareable state in the URL path or query, not in the `#fragment`.
- Never put a secret (private key, claim secret, seed phrase, session token, API key) in the URL path or query, encoded or not: every in-app path and query is mirrored to the visitor's studio.arc.io address bar and browser history and reaches servers. A bearer claim secret goes only in the `#fragment` appended to the share link (`` `${await buildShareLink('/claim')}#${secret}` ``) and is read from `location.hash` on load. A link to the app's own share URL shown inside the app must be copy-only or open in a new tab with `target="_blank" rel="noopener noreferrer"`.
- Build every link a user copies or sends with `buildShareLink()` from `src/lib/share.ts`.
- Keep the `installShareSync()` call in `src/main.tsx` when editing it; it keeps the Studio address bar in step with in-app navigation.
- Navigate inside the app with relative links.

## To Run

```bash
bun install
bun run dev
```

## Deployments
- PostPaidEscrow (Arc Testnet, chain 5042002): 0x4e51c6f82fb8dadd51d650607f05cbb937d3cfe5, tx 0xb762d3b1e21d6811e71d8bd9f8670f9e035be99a4149767a19f213931abbed88. USDC 0x3600000000000000000000000000000000000000, owner and feeRecipient 0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17, fee 100 bps.

## Frontend (PostPaid)
- Routes: `/` (Landing), `/new`, `/deal/:id`, `/dashboard` in `src/pages/`; components in `src/components/`, hooks in `src/hooks/`.
- Network config lives in `src/postpaid.ts` (env: VITE_CHAIN, VITE_ESCROW_ADDRESS, VITE_DEPLOY_BLOCK). ABI copy in `src/abi/postPaidEscrow.ts`.
- All writes go through `useSendTx` (simulate, 25 gwei / 1 gwei fee floors, toasts, refetch). Errors are decoded in `src/lib/errors.ts`.
- `milestoneActions` flags are state-only; role gating is done in `MilestoneCard` and `DealActions`.
- Timeline reads PostPaid logs only, filtered by the dealId topic, in chunks of 10,000 blocks from the deploy block.
