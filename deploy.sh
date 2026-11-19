#!/usr/bin/env bash
# Auto-Saver deploy orchestrator — DO NOT RUN until the deployer is funded.
# Funding needed (testnet only, no real money):
#   ~0.03 Base Sepolia ETH total:
#     - 0.02 ETH -> swap to 2 lREACT (see swap-lreact.sh, run FIRST)
#     - ~0.003 ETH -> SaveToken + Vault deploys + demo mint
#     - ~0.01 ETH -> vault funding (callback fees)
#   ~1.3 lREACT on Lasna -> RSC deploy + configure + RSC funding
#     (from the 2 lREACT above)
#
# Usage: ./deploy.sh
# The private key is read from ../deployer-keypair.json (mode 600) and is
# NEVER printed. Addresses land in deployments.env + frontend/config.json.
#
# Recovery: if this script is interrupted mid-broadcast, forge refuses to
# re-broadcast while recovery files exist. Either resume with
#   forge script <script> --resume --broadcast
# or delete the stale state (safe before any real funds moved) with
#   rm -rf broadcast cache
# and run ./deploy.sh again.
set -euo pipefail
cd "$(dirname "$0")"

export PATH="$HOME/.foundry/bin:$PATH"

BASE_SEPOLIA_RPC="https://sepolia.base.org"
LASNA_RPC="https://lasna-rpc.rnk.dev"
FAUCET_BASE_SEPOLIA="0x2afaFD298b23b62760711756088F75B7409f5967" # 1 ETH -> 100 lREACT

KEYFILE="../deployer-keypair.json"
if [ ! -f "$KEYFILE" ]; then echo "ERROR: $KEYFILE not found"; exit 1; fi
PRIVATE_KEY="$(python3 -c "import json; print(json.load(open('$KEYFILE'))['data'][0]['private_key'])")"
export PRIVATE_KEY
DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "Deployer: $DEPLOYER"
export DEPLOYER

# --- 0. Balance checks (abort with a clear message if short) -----------
BASE_BAL_WEI="$(cast balance "$DEPLOYER" --rpc-url "$BASE_SEPOLIA_RPC")"
LASNA_BAL_WEI="$(cast balance "$DEPLOYER" --rpc-url "$LASNA_RPC")"
echo "Base Sepolia balance: $(cast --to-unit "$BASE_BAL_WEI" ether) ETH"
echo "Lasna balance:        $(cast --to-unit "$LASNA_BAL_WEI" ether) lREACT"
if [ "$BASE_BAL_WEI" -lt 30000000000000000 ]; then
  echo "ERROR: need >= 0.03 Base Sepolia ETH (have $(cast --to-unit "$BASE_BAL_WEI" ether))."
  echo "Get it from a Base Sepolia faucet, e.g. https://app.optimism.io/faucet or https://faucets.chain.link/base-sepolia"
  exit 1
fi
if [ "$LASNA_BAL_WEI" -lt 500000000000000000 ]; then
  echo "ERROR: need >= 0.5 lREACT on Lasna (have $(cast --to-unit "$LASNA_BAL_WEI" ether))."
  echo "Run ./swap-lreact.sh first (swaps 0.02 Base Sepolia ETH -> 2 lREACT)."
  exit 1
fi

# --- 1. SaveToken on Base Sepolia -----------------------------------------
echo "=== [1/6] Deploying SaveToken (Base Sepolia) ==="
OUT="$(forge script script/DeployToken.s.sol --rpc-url "$BASE_SEPOLIA_RPC" --broadcast)"
echo "$OUT" | grep -E "SaveToken:|Owner"
TOKEN_ADDRESS="$(echo "$OUT" | grep -oP 'SaveToken: \K0x[0-9a-fA-F]{40}' | head -1)"
[ -n "$TOKEN_ADDRESS" ] || { echo "ERROR: could not parse SaveToken address"; exit 1; }
export TOKEN_ADDRESS

# --- 2. Mint 10,000 SAVE to the deployer (demo user) ----------------------
echo "=== [2/6] Minting 10,000 SAVE to deployer ==="
DEMO_USER="$DEPLOYER" MINT_AMOUNT=10000 \
  forge script script/MintDemo.s.sol --rpc-url "$BASE_SEPOLIA_RPC" --broadcast \
  | grep -E "SaveToken:|Minted|Amount"

# --- 3. RSC on Lasna -------------------------------------------------------
echo "=== [3/6] Deploying AutoSaverReactive (Lasna) ==="
OUT="$(forge script script/DeployReactive.s.sol --rpc-url "$LASNA_RPC" --broadcast)"
echo "$OUT" | grep -E "AutoSaverReactive:|Token:|Owner"
REACTIVE_ADDRESS="$(echo "$OUT" | grep -oP 'AutoSaverReactive: \K0x[0-9a-fA-F]{40}' | head -1)"
[ -n "$REACTIVE_ADDRESS" ] || { echo "ERROR: could not parse RSC address"; exit 1; }
export REACTIVE_ADDRESS

# --- 4. Vault on Base Sepolia ----------------------------------------------
echo "=== [4/6] Deploying AutoSaverVault (Base Sepolia) ==="
OUT="$(forge script script/DeployVault.s.sol --rpc-url "$BASE_SEPOLIA_RPC" --broadcast)"
echo "$OUT" | grep -E "AutoSaverVault:|CallbackSender"
VAULT_ADDRESS="$(echo "$OUT" | grep -oP 'AutoSaverVault: \K0x[0-9a-fA-F]{40}' | head -1)"
[ -n "$VAULT_ADDRESS" ] || { echo "ERROR: could not parse Vault address"; exit 1; }
export VAULT_ADDRESS

# --- 5. Wire RSC -> Vault, register demo user at 10% (Lasna) --------------
echo "=== [5/6] Configuring RSC: setVault + setSavingsPct(deployer, 10) ==="
REACTIVE_ADDRESS="$REACTIVE_ADDRESS" VAULT_ADDRESS="$VAULT_ADDRESS" \
  DEMO_USER="$DEPLOYER" SAVINGS_PCT=10 \
  forge script script/Configure.s.sol --rpc-url "$LASNA_RPC" --broadcast \
  | grep -E "RSC:|Vault set|Demo user|Savings pct"

# --- 6. Fund both contracts -------------------------------------------------
echo "=== [6/6] Funding: 0.01 Base Sepolia ETH -> Vault, 1 lREACT -> RSC ==="
cast send "$VAULT_ADDRESS" --value 0.01ether --rpc-url "$BASE_SEPOLIA_RPC" \
  --private-key "$PRIVATE_KEY" --confirmations 1 | grep -E "blockHash|transactionHash"
cast send "$REACTIVE_ADDRESS" --value 1ether --rpc-url "$LASNA_RPC" \
  --private-key "$PRIVATE_KEY" --confirmations 1 | grep -E "blockHash|transactionHash"

# --- Save addresses ----------------------------------------------------------
cat > deployments.env <<EOF
# Auto-Saver deployments (testnet) — generated by deploy.sh, do not edit by hand.
TOKEN_ADDRESS=$TOKEN_ADDRESS
REACTIVE_ADDRESS=$REACTIVE_ADDRESS
VAULT_ADDRESS=$VAULT_ADDRESS
DEPLOYER=$DEPLOYER
EOF

python3 - "$TOKEN_ADDRESS" "$REACTIVE_ADDRESS" "$VAULT_ADDRESS" <<'PYEOF'
import json, sys
cfg = {
    "token": sys.argv[1],
    "reactive": sys.argv[2],
    "vault": sys.argv[3],
    "baseSepoliaRpc": "https://sepolia.base.org",
    "lasnaRpc": "https://lasna-rpc.rnk.dev",
}
with open("frontend/config.json", "w") as f:
    json.dump(cfg, f, indent=2)
print("frontend/config.json written")
PYEOF

echo ""
echo "DEPLOY COMPLETE"
echo "  SaveToken (Base Sepolia): $TOKEN_ADDRESS"
echo "  AutoSaverReactive (Lasna): $REACTIVE_ADDRESS"
echo "  AutoSaverVault (Base Sepolia): $VAULT_ADDRESS"
echo "  Reactscan (RSC): https://lasna.reactscan.net/address/$REACTIVE_ADDRESS"
echo "  Basescan (Vault): https://sepolia.basescan.org/address/$VAULT_ADDRESS"
echo "  Basescan (Token): https://sepolia.basescan.org/address/$TOKEN_ADDRESS"
echo "Next: ./verify.sh  (Sourcify verification) and start the demo:"
echo "  cd frontend && python3 -m http.server 8000"
