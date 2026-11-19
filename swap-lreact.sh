#!/usr/bin/env bash
# Swap 0.02 Base Sepolia ETH -> 2 lREACT (Lasna) via the Reactive faucet contract.
# Rate: 1 ETH -> 100 lREACT. No login, no account — just send ETH to the
# faucet contract on Base Sepolia; lREACT arrives on Lasna at the same address.
# Run BEFORE deploy.sh. Testnet only, no real money.
set -euo pipefail
cd "$(dirname "$0")"

export PATH="$HOME/.foundry/bin:$PATH"
BASE_SEPOLIA_RPC="https://sepolia.base.org"
LASNA_RPC="https://lasna-rpc.rnk.dev"
FAUCET_BASE_SEPOLIA="0x2afaFD298b23b62760711756088F75B7409f5967"

KEYFILE="../deployer-keypair.json"
PRIVATE_KEY="$(python3 -c "import json; print(json.load(open('$KEYFILE'))['data'][0]['private_key'])")"
DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"

echo "Deployer: $DEPLOYER"
echo "Lasna lREACT before: $(cast --to-unit "$(cast balance "$DEPLOYER" --rpc-url "$LASNA_RPC")" ether)"
echo "Sending 0.02 Base Sepolia ETH to faucet $FAUCET_BASE_SEPOLIA ..."
cast send "$FAUCET_BASE_SEPOLIA" --value 0.02ether --rpc-url "$BASE_SEPOLIA_RPC" \
  --private-key "$PRIVATE_KEY" --confirmations 2 | grep -E "blockHash|transactionHash"
sleep 10
echo "Lasna lREACT after:  $(cast --to-unit "$(cast balance "$DEPLOYER" --rpc-url "$LASNA_RPC")" ether)"
echo "If the balance did not move yet, wait a minute and re-check with:"
echo "  cast balance $DEPLOYER --rpc-url $LASNA_RPC"
