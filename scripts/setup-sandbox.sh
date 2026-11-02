#!/usr/bin/env bash
# Rebuilds the PostPaid toolchain in a fresh Linux x86_64 sandbox (e.g. a new
# Claude Code cloud session). Every download is checksum-verified.
# Usage: bash scripts/setup-sandbox.sh
set -euo pipefail

ARC_FOUNDRY_TAG="v0.8.0-2"
ARC_FOUNDRY_SHA256="088bdb96a84418b757f9825d491e702792f1d1d1e29a9145af305a6600a79556"
SOLC_VERSION="0.8.38"
SOLC_SHA256="65c3180a336eabb6bdc4bbd49cc405aeb233976964ae6c11fba2a6c8be8f3243"  # matches solc-bin list.json

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Arc Foundry (Circle's Arc fork of Foundry), installed under the arc- prefix.
if ! command -v arc-forge >/dev/null 2>&1; then
  F="arc-foundry-${ARC_FOUNDRY_TAG}-x86_64-unknown-linux-gnu.tar.gz"
  curl -sSL -o "$TMP/$F" "https://github.com/circlefin/arc-foundry/releases/download/${ARC_FOUNDRY_TAG}/${F}"
  echo "${ARC_FOUNDRY_SHA256}  $TMP/$F" | sha256sum -c -
  tar -xzf "$TMP/$F" -C "$TMP"
  for b in forge cast anvil; do install -m 0755 "$TMP/$b" "$BIN/arc-$b"; done
fi

# 2. solc from the official GitHub release (binaries.soliditylang.org may be blocked).
SOLC="$HOME/.svm/${SOLC_VERSION}/solc-${SOLC_VERSION}"
if [ ! -x "$SOLC" ]; then
  mkdir -p "$(dirname "$SOLC")"
  curl -sSL -o "$TMP/solc" "https://github.com/ethereum/solidity/releases/download/v${SOLC_VERSION}/solc-static-linux"
  echo "${SOLC_SHA256}  $TMP/solc" | sha256sum -c -
  install -m 0755 "$TMP/solc" "$SOLC"
fi

# 3. Contract libraries, laid out like the Arc Studio workspace:
#    forge-std as a git submodule in lib/, OpenZeppelin 5.6.1 from npm (node_modules/).
cd "$(dirname "$0")/.."
git submodule update --init --recursive
[ -d node_modules/@openzeppelin/contracts ] || npm install --no-save --no-package-lock @openzeppelin/contracts@5.6.1

# 4. Arc Studio CLI (needs studio.arc.io reachable + ARC_STUDIO_TOKEN to be useful).
if ! command -v arc-studio >/dev/null 2>&1; then
  npm install -g @circle-fin/arc-studio-cli@1.2.2
fi

export PATH="$BIN:$PATH"
arc-forge --version | head -1
"$SOLC" --version | tail -1
arc-studio --version 2>/dev/null || true
echo "Done. Add to your shell: export PATH=\"$BIN:\$PATH\""
