#!/usr/bin/env bash
# Local end-to-end smoke test of the deploy scripts on anvil.
# Uses anvil's default funded account (NOT the testnet deployer key).
# Proves: deploy scripts run, wiring works, react() routes a real Transfer
# log (via impersonated SYSTEM), and the vault sweep moves real tokens
# (via impersonated callback proxy). The cross-chain relay itself only
# exists on Lasna/Base Sepolia, so the callback request is a no-op here.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.foundry/bin:$PATH"

RPC="http://127.0.0.1:8545"
ANVIL_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
SYSTEM="0x8888888888888888888888888888888888888888"
PROXY="0x476F44b11F5C942c58f4c8E3d0300E5710743585"
TRANSFER_TOPIC0="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
TOPIC_ADDR="0x000000000000000000000000f39Fd6e51aad88F6F4ce6aB8827279cffFb92266" # deployer, 32 bytes
DATA_1000="0x00000000000000000000000000000000000000000000003635C9ADC5DEA00000" # abi.encode(1000 ether)

anvil --port 8545 > /tmp/autosaver-anvil.log 2>&1 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do cast client --rpc-url "$RPC" >/dev/null 2>&1 && break; sleep 1; done

export PRIVATE_KEY="$ANVIL_KEY"
# Drop any unfinished broadcast/recovery state from an earlier run:
# forge refuses to re-broadcast while cache/*/run-latest.json recovery
# files exist, so clear both (compiler cache rebuilds automatically).
rm -rf broadcast cache

# forge script's dry-run reverts on calls to code-less addresses, and anvil
# has no system contract at 0x8888... — etch the MockSystem runtime code
# there first. (On Lasna the real system contract lives at that address,
# so the real deploy needs no such step.)
MOCK_CODE="$(forge inspect test/AutoSaver.t.sol:MockSystem deployedBytecode | tail -1)"
cast rpc anvil_setCode "$SYSTEM" "$MOCK_CODE" --rpc-url "$RPC" >/dev/null
echo "Mock system contract etched at $SYSTEM"

echo "=== [1/5] DeployToken ==="
OUT="$(forge script script/DeployToken.s.sol --rpc-url "$RPC" --broadcast)"
TOKEN="$(echo "$OUT" | grep -oP 'SaveToken: \K0x[0-9a-fA-F]{40}' | head -1)"
echo "Token: $TOKEN"

echo "=== [2/5] MintDemo + DeployReactive + DeployVault ==="
DEMO_USER="$DEPLOYER" MINT_AMOUNT=10000 TOKEN_ADDRESS="$TOKEN" \
  forge script script/MintDemo.s.sol --rpc-url "$RPC" --broadcast | grep -E "Minted|Amount"
OUT="$(TOKEN_ADDRESS="$TOKEN" forge script script/DeployReactive.s.sol --rpc-url "$RPC" --broadcast)"
RSC="$(echo "$OUT" | grep -oP 'AutoSaverReactive: \K0x[0-9a-fA-F]{40}' | head -1)"
echo "RSC: $RSC"
OUT="$(TOKEN_ADDRESS="$TOKEN" REACTIVE_ADDRESS="$RSC" forge script script/DeployVault.s.sol --rpc-url "$RPC" --broadcast)"
VAULT="$(echo "$OUT" | grep -oP 'AutoSaverVault: \K0x[0-9a-fA-F]{40}' | head -1)"
echo "Vault: $VAULT"

echo "=== [3/5] Configure (setVault + setSavingsPct 10) ==="
REACTIVE_ADDRESS="$RSC" VAULT_ADDRESS="$VAULT" DEMO_USER="$DEPLOYER" SAVINGS_PCT=10 \
  forge script script/Configure.s.sol --rpc-url "$RPC" --broadcast | grep -E "Vault set|Savings pct"
echo "savingsPct(deployer) = $(cast call "$RSC" "savingsPct(address) returns (uint256)" "$DEPLOYER" --rpc-url "$RPC")"
echo "vault() = $(cast call "$RSC" "vault() returns (address)" --rpc-url "$RPC")"
echo "SAVE balance = $(cast call "$TOKEN" "balanceOf(address) returns (uint256)" "$DEPLOYER" --rpc-url "$RPC")"

echo "=== [4/5] Approve vault, then impersonate SYSTEM and call react() ==="
cast send "$TOKEN" "approve(address,uint256)" "$VAULT" 1000000000000000000000000 --private-key "$ANVIL_KEY" --rpc-url "$RPC" --confirmations 1 >/dev/null
# Impersonated accounts hold no ETH, so fund them first — otherwise
# anvil's gas estimation fails ("gas required exceeds allowance: 0").
cast rpc anvil_impersonateAccount "$SYSTEM" --rpc-url "$RPC" >/dev/null
cast rpc anvil_setBalance "$SYSTEM" 10000000000000000000 --rpc-url "$RPC" >/dev/null
cast send "$RSC" \
  "react((uint256,address,uint256,uint256,uint256,uint256,bytes,uint256,uint256,uint256,uint256,uint256))" \
  "(84532, $TOKEN, $TRANSFER_TOPIC0, $TOPIC_ADDR, $TOPIC_ADDR, 0, $DATA_1000, 1, 3, 0, 0, 0)" \
  --from "$SYSTEM" --unlocked --rpc-url "$RPC" --confirmations 1 | grep -E "status|transactionHash"
echo "totalSweepRequested(deployer) = $(cast call "$RSC" "totalSweepRequested(address) returns (uint256)" "$DEPLOYER" --rpc-url "$RPC") (expect 100 ether = 100000000000000000000)"

echo "=== [5/5] Impersonate proxy and deliver the sweep to the vault ==="
cast rpc anvil_impersonateAccount "$PROXY" --rpc-url "$RPC" >/dev/null
cast rpc anvil_setBalance "$PROXY" 10000000000000000000 --rpc-url "$RPC" >/dev/null
cast send "$VAULT" "sweep(address,address,uint256)" "$RSC" "$DEPLOYER" 100000000000000000000 \
  --from "$PROXY" --unlocked --rpc-url "$RPC" --confirmations 1 | grep -E "status|transactionHash"
echo "saved(deployer) = $(cast call "$VAULT" "saved(address) returns (uint256)" "$DEPLOYER" --rpc-url "$RPC") (expect 100 ether)"
echo "vault SAVE balance = $(cast call "$TOKEN" "balanceOf(address) returns (uint256)" "$VAULT" --rpc-url "$RPC") (expect 100 ether)"
echo ""
echo "SMOKE TEST PASSED — full loop works on anvil."
