#!/usr/bin/env bash
# Starts anvil, deploys mocks + FarmersMarket, and serves the UI at http://localhost:5173
set -euo pipefail
cd "$(dirname "$0")/.."

# Load PRIVATE_KEY (and anything else) from .env if present
if [[ -f .env ]]; then set -a; source .env; set +a; fi
# Default: anvil account #0 — public dev key, local use only
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

anvil --silent &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null' EXIT
until cast chain-id --rpc-url http://127.0.0.1:8545 >/dev/null 2>&1; do sleep 0.2; done

forge script script/DeployLocal.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key "$PRIVATE_KEY" | grep -A3 "== Logs =="

echo "UI → http://localhost:5173  (Ctrl+C stops anvil + server)"
python3 -m http.server 5173 --directory ui
