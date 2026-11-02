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

### Testnet demo run — 2026-11-02 (deal #1, "PostPaid launch campaign") ✅

Run with `scripts/demo-testnet.sh` (raw log: [`testnet-demo.tsv`](testnet-demo.tsv)). All steps succeeded.

| # | Actor | Action | Tx |
|---|---|---|---|
| 0a | Brand | gas top-up → creator (0.30 USDC) | [`0x41249cc2…a67517`](https://explorer.testnet.arc.io/tx/0x41249cc24259ad6555f367073cfcb10e7c4727ccd4de53fcb5e51f0dbca67517) |
| 0b | Brand | gas top-up → keeper (0.30 USDC) | [`0xdd881e6a…c5fd1c`](https://explorer.testnet.arc.io/tx/0xdd881e6abcb231d8d588128e120696cf07d223f8dac95087efde0e93f4c5fd1c) |
| 1 | Brand | approve 0.90 USDC | [`0x814ffac3…70e9fa`](https://explorer.testnet.arc.io/tx/0x814ffac36df36bf83d012c838bae94bb32ffff43e6b5c42e5d19d33c6270e9fa) |
| 2 | Brand | createDeal #1 'PostPaid launch campaign' (0.90 USDC into escrow) | [`0x1eb5bbb1…190b89`](https://explorer.testnet.arc.io/tx/0x1eb5bbb10501868261185af829d7f61e8f8028c7d4fc96ead0c5d67dd1190b89) |
| 3 | Creator | acceptDeal #1 | [`0xee1524dd…fab85f`](https://explorer.testnet.arc.io/tx/0xee1524ddc8da9117632060f5438bd431955f2a415d70152d6e563261affab85f) |
| 4 | Creator | submitMilestone M1 (proof URL) | [`0x37408fd3…e42cf0`](https://explorer.testnet.arc.io/tx/0x37408fd38572d774a7c85e885504e0071bb874398a0755d1a01ef729c3e42cf0) |
| 5 | Brand | approveMilestone M1 | [`0xbbc0f185…5f4244`](https://explorer.testnet.arc.io/tx/0xbbc0f1851af3f2e171d311d69757638f6a2d78b57ecc536ee50e1663775f4244) |
| 6 | Creator | withdraw (creator, 0.297 USDC) | [`0xf5738180…68e93a`](https://explorer.testnet.arc.io/tx/0xf5738180438b60af7149bced08a379e0a67c33e39868847c12b7cc54c668e93a) |
| 7a | Creator | submitMilestone M2 | [`0x3468ffb6…450c35`](https://explorer.testnet.arc.io/tx/0x3468ffb6884b585a4ec2b0b1da0e61609fc60439e07bf061ceb4981ac0450c35) |
| 7b | Keeper (anyone) | claimAfterTimeout M2 (by third party) | [`0xcbc52d10…c1f03e`](https://explorer.testnet.arc.io/tx/0xcbc52d10f776c4efa93d97e32f67bb84ec3f0cd1c68c8b054d94301744c1f03e) |
| 8 | Keeper (anyone) | refundMilestone M3 (by third party → brand) | [`0x46c10ad8…d09c77`](https://explorer.testnet.arc.io/tx/0x46c10ad8ac65570e17339adb53897fe80fe9c91cd31a95b7d3f7c4e3b1d09c77) |
| 9a | Creator | withdraw (creator, 0.297 USDC) | [`0x4b9de382…f0c64a`](https://explorer.testnet.arc.io/tx/0x4b9de382366e15fd09180fa4c0631d751b23f8039ee27aebbddec684acf0c64a) |
| 9b | Brand | withdraw (brand refund, 0.30 USDC) | [`0x97ca0ca8…6a2055`](https://explorer.testnet.arc.io/tx/0x97ca0ca8abaafc3dad7d67ec127dc373797b2e547be0a4e3510d3f5d366a2055) |

**End state, read on-chain:** deal #1 is `Closed` (status 3), `escrowed = 0`. The creator received 2 × 0.297 = 0.594 USDC, the brand got its 0.30 USDC M3 refund back, and the fee recipient (`0x553f…CA17`) has 0.006 USDC credited, not yet withdrawn (it's Greg's wallet). The contract holds exactly that 0.006 USDC.

Note: one transient `-32603 internal error` from the testnet RPC hit a read-only poll while waiting. The script retried and nothing was affected.
