#!/usr/bin/env bash
# Verify all three contracts on Sourcify (Lasna + Base Sepolia explorers).
# Run after deploy.sh. Reads addresses from deployments.env.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

[ -f deployments.env ] || { echo "ERROR: run ./deploy.sh first"; exit 1; }
# shellcheck disable=SC1091
source deployments.env

echo "Verifying SaveToken on Base Sepolia (84532)..."
forge verify-contract --verifier sourcify --chain-id 84532 \
  "$TOKEN_ADDRESS" src/SaveToken.sol:SaveToken || echo "SaveToken verify failed (retry later)"
echo "Verifying AutoSaverVault on Base Sepolia (84532)..."
forge verify-contract --verifier sourcify --chain-id 84532 \
  "$VAULT_ADDRESS" src/AutoSaverVault.sol:AutoSaverVault || echo "Vault verify failed (retry later)"
echo "Verifying AutoSaverReactive on Lasna (5318007)..."
forge verify-contract --verifier sourcify --chain-id 5318007 \
  "$REACTIVE_ADDRESS" src/AutoSaverReactive.sol:AutoSaverReactive || echo "RSC verify failed (retry later)"
echo "Done."
