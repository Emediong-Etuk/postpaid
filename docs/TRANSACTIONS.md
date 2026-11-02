# Transactions

## Arc mainnet (chain 5042)

| Item | Value |
|---|---|
| PostPaidEscrow | — |
| Deploy tx | — |
| Deploy block | — |

| # | Step | Actor | Tx hash | Explorer |
|---|---|---|---|---|

## Arc testnet (chain 5042002) — rehearsal

| Item | Value |
|---|---|
| PostPaidEscrow | [`0x4e51c6f82fb8dadd51d650607f05cbb937d3cfe5`](https://explorer.testnet.arc.io/address/0x4e51c6f82fb8dadd51d650607f05cbb937d3cfe5) (source verified ✅) |
| Deployed by | Arc Studio (turn #3), deployer `0xafc0e36e0a77a40b748fe6db681858648d1652af` |
| Deploy tx | [`0xb762d3b1…bed88`](https://explorer.testnet.arc.io/tx/0xb762d3b1e21d6811e71d8bd9f8670f9e035be99a4149767a19f213931abbed88) |
| Deploy block | 70378581 |
| Constructor | usdc `0x3600…0000`, owner & feeRecipient `0x553f…CA17`, fee 100 bps |

On-chain checks (Claude, independently of Studio's report): receipt status 1. The read-backs match the constructor. The deployed runtime bytecode equals our local build byte for byte, except the 5 immutable-`usdc` slots, and the metadata hash matches too.

Testnet demo wallets (throwaway, testnet only): brand `0xceb064097AEc90d68302DE251C8f6dea662d4E22`, creator `0xa242E7dEA27Ff02Bc39142f0115f369527cABde3`, keeper `0x6D2Ac7C0226e2B853279051091257392178a3F1c`.

Demo transactions: see [`testnet-demo.tsv`](testnet-demo.tsv) (filled by `scripts/demo-testnet.sh`).
