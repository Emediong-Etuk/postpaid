# Mainnet deploy — PostPaidEscrow on Arc mainnet (chain 5042)

Greg signs. Claude never sees a private key or seed phrase.

**Constructor** (fixed in `contracts/script/DeployPostPaid.s.sol`):

| Argument | Value |
|---|---|
| `usdc` | `0x3600000000000000000000000000000000000000` |
| `initialOwner` | `0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17` (wallet A) |
| `feeRecipient` | `0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17` (wallet A) |
| `initialFeeBps` | `100` (1%) |

**Cost:** about 3.43M gas. At about 21 gwei that's **≈ 0.07 USDC** of gas, paid from wallet A.
**Before you start:** wallet A holds ≥ 2 USDC on Arc mainnet (≈ 0.07 for the deploy, 0.90 for the demo deal, plus gas for the demo).
**Gas:** `maxFeePerGas` must be ≥ 20 gwei. Arc silently drops anything lower.

Rehearsed on 2026-11-02 against an Arc-mode fork of Arc Testnet: the deploy succeeded and the script's checks of owner, fee, fee recipient and USDC passed.

---

## Option B: Arc Foundry from your own computer (macOS Apple Silicon or Linux)

1. Install Arc Foundry from https://github.com/circlefin/arc-foundry/releases. Download the archive for your platform, check its `.sha256`, and put `forge` / `cast` on your PATH as `arc-forge` / `arc-cast` (see the release README).
2. Get the repo and its dependencies:
   ```bash
   git clone --recurse-submodules https://github.com/Emediong-Etuk/postpaid && cd postpaid
   ```
   ```bash
   npm install --no-save --no-package-lock @openzeppelin/contracts@5.6.1
   ```
3. Import wallet A into an **encrypted** keystore. It prompts for the private key and a password; nothing is stored in plain text:
   ```bash
   arc-cast wallet import postpaid-owner --interactive
   ```
4. Deploy. It asks for the keystore password:
   ```bash
   arc-forge script contracts/script/DeployPostPaid.s.sol:DeployPostPaid --rpc-url https://rpc.mainnet.arc.io --account postpaid-owner --sender 0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17 --broadcast --with-gas-price 30gwei --priority-gas-price 1gwei
   ```
5. Send Claude the printed address and transaction hash. Claude verifies the bytecode and constructor on-chain, verifies the source on explorer.arc.io (`scripts/verify-blockscout.sh mainnet …`), and switches the app to mainnet.

**Note:** step 3 means exporting wallet A's private key from your browser wallet once. If you'd rather not, use Option A.

## Option A: one-click deploy from the browser wallet (no CLI, no key export)

A small, unlisted deploy page in the app (built in Arc Studio). It sends the contract-creation transaction from MetaMask/Rabby with the bytecode and constructor values above, refuses to run unless the connected wallet is wallet A on Arc mainnet, and shows the address and transaction hash. Claude rehearses it on a testnet fork first, then verifies the result on-chain exactly as in Option B. **This needs Greg's OK first** (it's an addition to the spec's deploy plan).
