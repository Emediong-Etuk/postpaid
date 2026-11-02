#!/usr/bin/env bash
# Verify PostPaidEscrow on an Arc Blockscout explorer by submitting standard-JSON input.
# Used because `arc-forge verify-contract` needs binaries.soliditylang.org, which can be blocked.
# The JSON is rebuilt from the forge artifact's metadata and checked to reproduce the exact bytecode first.
#
# Usage: scripts/verify-blockscout.sh <testnet|mainnet> <address> <owner> <feeRecipient> <feeBps>
set -euo pipefail
NET=$1 ADDR=$2 OWNER=$3 FEE_TO=$4 FEE_BPS=$5
case "$NET" in
  testnet) EXPLORER=https://explorer.testnet.arc.io ;;
  mainnet) EXPLORER=https://explorer.arc.io ;;
  *) echo "network must be testnet or mainnet" >&2; exit 1 ;;
esac
USDC=0x3600000000000000000000000000000000000000
SOLC_VERSION=0.8.38
SOLC_LONG=v0.8.38+commit.1835d247
SOLC="$HOME/.svm/$SOLC_VERSION/solc-$SOLC_VERSION"
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

arc-forge build --network arc >/dev/null
python3 -I - "$TMP/std.json" <<'PY'
import json, os, sys
art = json.load(open("contracts/out/PostPaidEscrow.sol/PostPaidEscrow.json"))
meta = art.get("rawMetadata") or art["metadata"]
meta = json.loads(meta) if isinstance(meta, str) else meta
st = meta["settings"]
rem = [r.lstrip(":").split("=", 1) for r in st.get("remappings", [])]
srcs = {}
for p in meta["sources"]:
    fp = p
    if not os.path.exists(fp):
        for a, b in rem:
            if p.startswith(a):
                fp = b + p[len(a):]
                break
    srcs[p] = {"content": open(fp).read()}
settings = {k: st[k] for k in ("remappings", "optimizer", "evmVersion", "metadata", "libraries", "viaIR") if k in st}
settings["outputSelection"] = {"*": {"*": ["abi", "evm.bytecode", "evm.deployedBytecode", "metadata"]}}
json.dump({"language": "Solidity", "sources": srcs, "settings": settings}, open(sys.argv[1], "w"))
PY
"$SOLC" --standard-json "$TMP/std.json" > "$TMP/out.json"
python3 -I - "$TMP/out.json" <<'PY'
import json, sys
out = json.load(open(sys.argv[1]))
rt = out["contracts"]["contracts/PostPaidEscrow.sol"]["PostPaidEscrow"]["evm"]["deployedBytecode"]["object"].lower()
art = json.load(open("contracts/out/PostPaidEscrow.sol/PostPaidEscrow.json"))["deployedBytecode"]["object"][2:].lower()
assert rt == art, "standard-JSON does not reproduce the forge bytecode"
print("standard-JSON reproduces the forge bytecode")
PY
ARGS=$(arc-cast abi-encode "constructor(address,address,address,uint16)" $USDC "$OWNER" "$FEE_TO" "$FEE_BPS")
curl -sS -X POST "$EXPLORER/api/v2/smart-contracts/$ADDR/verification/via/standard-input" \
  -F compiler_version=$SOLC_LONG -F contract_name=PostPaidEscrow -F license_type=mit \
  -F autodetect_constructor_args=false -F constructor_args="${ARGS#0x}" \
  -F "files[0]=@$TMP/std.json;type=application/json"; echo
for _ in $(seq 1 18); do
  v=$(curl -sS "$EXPLORER/api/v2/smart-contracts/$ADDR" | python3 -I -c "import json,sys; d=json.load(sys.stdin); print(d.get('is_fully_verified'))" 2>/dev/null || true)
  [ "$v" = "True" ] && { echo "Verified: $EXPLORER/address/$ADDR?tab=contract"; exit 0; }
  sleep 10
done
echo "Not verified yet; check $EXPLORER/address/$ADDR" >&2; exit 1
