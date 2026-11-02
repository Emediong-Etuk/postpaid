#!/usr/bin/env bash
# Wrapper for the Arc Studio CLI inside the Claude Code cloud sandbox.
# Node's built-in fetch ignores HTTPS_PROXY unless NODE_USE_ENV_PROXY=1, and the
# sandbox proxy needs its CA bundle; without these the CLI reports "token rejected".
set -euo pipefail
export NODE_USE_ENV_PROXY=1
[ -f /root/.ccr/ca-bundle.crt ] && export NODE_EXTRA_CA_CERTS=/root/.ccr/ca-bundle.crt
export ARC_STUDIO_NO_HYPERLINKS=1
export NODE_NO_WARNINGS=1
exec arc-studio "$@"
