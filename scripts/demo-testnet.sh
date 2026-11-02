#!/usr/bin/env bash
# PostPaid — §9 Step C demo, rehearsed on ARC TESTNET with throwaway testnet-only keystores.
# Every transaction hash is appended to docs/testnet-demo.tsv.
#
# Wallets (encrypted keystores in ~/.foundry/keystores, password in ~/.postpaid-testnet/pw):
#   pp-testnet-brand    — brand A (funded from faucet.circle.com)
#   pp-testnet-creator  — creator B
#   pp-testnet-keeper   — a third party ("anyone") for claimAfterTimeout / refundMilestone
#
# Usage: scripts/demo-testnet.sh <escrow-address>
# Takes ~25 minutes (10-minute review window, M3 due in 20 minutes).
set -euo pipefail
ESCROW=${1:?escrow address}
RPC=https://rpc.testnet.arc.io
EXPLORER=https://explorer.testnet.arc.io
USDC=0x3600000000000000000000000000000000000000
KS=$HOME/.foundry/keystores
PW=$HOME/.postpaid-testnet/pw
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."
LOG=docs/testnet-demo.tsv
[ -f "$LOG" ] || printf "step\tactor\taction\ttx\n" > "$LOG"

# Amounts in 6-decimal USDC units (parseUnits(x, 6)): 0.30 USDC = 300000, 0.90 USDC = 900000.
M=300000
TOTAL=900000
GAS_TOPUP=300000          # 0.30 USDC of gas for creator and keeper (gas is paid in USDC)
# Arc mempool drops maxFeePerGas < 20 gwei. Use 30 gwei max fee, 1 gwei tip.
FEES=(--gas-price 30gwei --priority-gas-price 1gwei)

addr() { arc-cast wallet address --keystore "$KS/$1" --password-file "$PW"; }
BRAND=$(addr pp-testnet-brand); CREATOR=$(addr pp-testnet-creator); KEEPER=$(addr pp-testnet-keeper)

send() { # send <step> <actor-keystore> <label> <to> <sig> [args...]
  local step=$1 who=$2 label=$3 to=$4; shift 4
  local out hash status
  out=$(arc-cast send "$to" "$@" --rpc-url "$RPC" --keystore "$KS/$who" --password-file "$PW" "${FEES[@]}" --json)
  hash=$(echo "$out" | python3 -I -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])")
  status=$(echo "$out" | python3 -I -c "import json,sys; print(json.load(sys.stdin)['status'])")
  [ "$status" = "0x1" ] || { echo "step $step FAILED: $hash" >&2; exit 1; }
  printf "%s\t%s\t%s\t%s\n" "$step" "$who" "$label" "$hash" >> "$LOG"
  echo "[$step] $label  $EXPLORER/tx/$hash"
}
bal() { arc-cast call $USDC "balanceOf(address)(uint256)" "$1" --rpc-url "$RPC" | awk '{print $1}'; }
now() { arc-cast block latest -f timestamp --rpc-url "$RPC"; }
actions() { arc-cast call "$ESCROW" "milestoneActions(uint256,uint256)(bool,bool,bool,bool,bool,bool,bool,uint64)" "$1" "$2" --rpc-url "$RPC" | tr '\n' ' '; }

echo "brand $BRAND  creator $CREATOR  keeper $KEEPER"
echo "brand USDC: $(bal "$BRAND") (need >= $((TOTAL + 2*GAS_TOPUP + 100000)))"

# 0. Gas top-ups from the brand (ERC-20 transfer; same balance as native gas).
[ "$(bal "$CREATOR")" -ge 100000 ] || send 0a pp-testnet-brand "gas top-up → creator (0.30 USDC)" $USDC "transfer(address,uint256)" "$CREATOR" $GAS_TOPUP
[ "$(bal "$KEEPER")" -ge 100000 ] || send 0b pp-testnet-brand "gas top-up → keeper (0.30 USDC)" $USDC "transfer(address,uint256)" "$KEEPER" $GAS_TOPUP

# 1–2. Approve exactly 0.90 USDC, then create the deal.
send 1 pp-testnet-brand "approve 0.90 USDC" $USDC "approve(address,uint256)" "$ESCROW" $TOTAL
T=$(now); D1=$((T + 86400)); D3=$((T + 1200))
ID=$(arc-cast call "$ESCROW" "nextDealId()(uint256)" --rpc-url "$RPC" | awk '{print $1}')
send 2 pp-testnet-brand "createDeal #$ID 'PostPaid launch campaign' (0.90 USDC into escrow)" "$ESCROW" \
  "createDeal(address,address,string,string,string[],uint256[],uint64[],uint32,uint8)" \
  "$CREATOR" 0x0000000000000000000000000000000000000000 "PostPaid launch campaign" "https://github.com/Emediong-Etuk/postpaid" \
  "[\"Launch thread\",\"Follow-up thread\",\"Spaces shoutout\"]" "[$M,$M,$M]" "[$D1,$D1,$D3]" 600 1
echo "escrow USDC: $(bal "$ESCROW")"

# 3–6. Accept, submit M1, approve M1, creator withdraws.
send 3 pp-testnet-creator "acceptDeal #$ID" "$ESCROW" "acceptDeal(uint256)" "$ID"
send 4 pp-testnet-creator "submitMilestone M1 (proof URL)" "$ESCROW" "submitMilestone(uint256,uint256,string)" "$ID" 0 "https://x.com/gregwrites_yy"
send 5 pp-testnet-brand "approveMilestone M1" "$ESCROW" "approveMilestone(uint256,uint256)" "$ID" 0
send 6 pp-testnet-creator "withdraw (creator, 0.297 USDC)" "$ESCROW" "withdraw()"

# 7. Submit M2, wait out the 10-minute review window, keeper claims (silence = approval).
send 7a pp-testnet-creator "submitMilestone M2" "$ESCROW" "submitMilestone(uint256,uint256,string)" "$ID" 1 "https://x.com/gregwrites_yy"
echo "waiting for M2 review window (10 min)…"
until actions "$ID" 1 | awk '{exit !($5=="true")}'; do sleep 20; done
send 7b pp-testnet-keeper "claimAfterTimeout M2 (by third party)" "$ESCROW" "claimAfterTimeout(uint256,uint256)" "$ID" 1

# 8. Wait for M3's due date (20 min after creation), keeper refunds it to the brand.
echo "waiting for M3 due date…"
until actions "$ID" 2 | awk '{exit !($6=="true")}'; do sleep 20; done
send 8 pp-testnet-keeper "refundMilestone M3 (by third party → brand)" "$ESCROW" "refundMilestone(uint256,uint256)" "$ID" 2

# 9. Withdrawals.
send 9a pp-testnet-creator "withdraw (creator, 0.297 USDC)" "$ESCROW" "withdraw()"
send 9b pp-testnet-brand "withdraw (brand refund, 0.30 USDC)" "$ESCROW" "withdraw()"

STATUS=$(arc-cast call "$ESCROW" "getDeal(uint256)((address,address,address,uint64,uint32,uint16,uint8,uint8,uint256,uint256,string,string))" "$ID" --rpc-url "$RPC")
echo "deal: $STATUS"
echo "fee recipient credit (0.006 USDC expected): $(arc-cast call "$ESCROW" "withdrawable(address)(uint256)" 0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17 --rpc-url "$RPC")"
echo "escrow USDC left (fee credit only): $(bal "$ESCROW")"
echo "DONE"
