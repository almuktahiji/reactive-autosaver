# Auto-Saver — Reactive Omni Buildathon

**Set it once, forget it.** Every time you receive SAVE tokens, a reactive
contract automatically sweeps a percentage you chose into your savings vault.
No app to open, no button to tap, no reminder — saving just happens.

Built for the [Reactive Omni Buildathon](https://dorahacks.io/) (DoraHacks),
track **"Set It and Forget It"** ($2,000 first / $250 runner-up, paid in REACT).

> **TESTNET ONLY.** This build runs on **Lasna** (Reactive testnet) +
> **Base Sepolia**. No mainnet, no real funds, no real value anywhere.
> The track text says "Reactive contracts on Reactive Mainnet, verified" —
> mainnet needs bought REACT, so this entry is deliberately testnet-only and
> says so openly. "Verified" here means source-verified on the testnet
> explorers (see `verify.sh`).

## How it works

```
You receive SAVE
      │
      ▼  Transfer event on Base Sepolia (chain 84532)
AutoSaverReactive.react()  ── Lasna (chain 5318007)
      │  · checks the recipient registered a savings %
      │  · sweep = amount × pct / 100
      ▼  requestCallbackV_1_0 → AutoSaverVault.sweep()
AutoSaverVault.sweep()  ── Base Sepolia
      │  · authenticated: onlyServiceProvider (callback proxy)
      │    + onlyCallbackSender (the RSC address)
      ▼  token.transferFrom(user → vault, sweep)
Your vault balance grows. You did nothing.
```

```
                    ┌─────────────────────┐
   Transfer event   │  AutoSaverReactive  │   callback
  ────────────────► │  (Lasna, RSC)       │ ────────────────►
  Base Sepolia      │  · subscribes to    │   system contract
  SaveToken         │    SaveToken        │
                    │    Transfer events  │                    ┌──────────────────┐
                    │  · looks up pct     │                    │ AutoSaverVault   │
                    │  · requests sweep   │                    │ (Base Sepolia)   │
                    └─────────────────────┘                    │ · pulls sweep via│
                                                               │   transferFrom   │
                                                               │ · holds savings  │
                                                               └──────────────────┘
```

Contracts (`src/`):

| Contract | Chain | Base | What it does |
|---|---|---|---|
| `SaveToken` | Base Sepolia | OpenZeppelin ERC20 | Demo savings asset. Owner mint + public faucet (10,000 SAVE). |
| `AutoSaverReactive` | Lasna | `AbstractReactive` | Subscribes to `SaveToken` Transfers; on a match, requests a callback to sweep `pct%` to the vault. |
| `AutoSaverVault` | Base Sepolia | `AbstractCallback` | Receives the callback, pulls the sweep from the user via `transferFrom`, tracks savings per user. |

Reactive base contracts come from the canonical
[`Reactive-Network/reactive-lib-omni`](https://github.com/Reactive-Network/reactive-lib-omni)
repo (installed via `forge install`, imported as `@reactive/src/...`).
All application logic is written fresh for this event. OpenZeppelin is used
as a library (ERC20, Ownable, SafeERC20).

Key design points:

- `react()` **never reverts as a filter**: non-matching logs (wrong topic,
  wrong `opCode`, wrong chain/contract, unregistered user, 0% or 0 sweep)
  fall through silently — a revert would still be billed.
- The callback payload reserves its first argument for the RSC address
  (the proxy overwrites it); the vault checks **both**
  `onlyServiceProvider` and `onlyCallbackSender`.
- Users approve the vault **once**; every later sweep is automatic.
- `coverDebt()` is open to anyone, per the Reactive docs, so a third party
  can top up a contract and restart it.

## Setup

```bash
forge build
forge test        # 24 tests, all green
```

Deploy (needs the throwaway testnet deployer — see `deploy.sh` header for
funding; **do not run until funded**):

```bash
./swap-lreact.sh  # 0.015 Base Sepolia ETH -> 1.5 lREACT (run first)
./deploy.sh       # deploys token -> RSC -> vault, wires them, funds both
./verify.sh       # Sourcify verification on both testnets
```

`deploy.sh` reads the throwaway deployer key from
`../deployer-keypair.json` (mode 600, never printed) and writes the
addresses to `deployments.env` and `frontend/config.json`.

Demo frontend (static HTML+JS, ethers via CDN):

```bash
cd frontend && python3 -m http.server 8000
# open http://localhost:8000
```

Flow in the demo: connect wallet (Base Sepolia) → get test SAVE → approve
the vault → send 100 SAVE to yourself (you are the pre-registered
recipient at 10%) → watch 10 SAVE land in the vault when the callback
confirms. Every transaction links to its explorer.

## Live deployment — proven on testnet

Demo video (2:21): https://www.youtube.com/watch?v=TZzzYCTF0z4

| Contract | Chain | Address |
|---|---|---|
| SaveToken | Base Sepolia (84532) | 0x45e352624332b1947957f1961ad2119859186E84 |
| AutoSaverReactive | Lasna (5318007) | 0x9C12cA13DfA4A010faca2d8aeDFF972Ac21203A8 |
| AutoSaverVault | Base Sepolia (84532) | 0x2A182e140Fa778c02F36284191853f4ef669914D |

All three contracts are **verified exact_match on Sourcify**. The RSC is
configured with the vault and a 10% savings rate for the demo user.

### The full loop, live (20 Nov 2026, real transactions — not a simulation)

1. Trigger: self-transfer of **1,000 SAVE** to the registered demo user —
   [tx 0x9f0cbc47ae2848205e0927aa15df5754978ec1b9b16f5410af119e593088756e](https://sepolia.basescan.org/tx/0x9f0cbc47ae2848205e0927aa15df5754978ec1b9b16f5410af119e593088756e)
   (block 61160883).
2. The RSC on Lasna saw the Transfer event, computed the 10% sweep and
   requested the callback.
3. Sweep: the vault pulled exactly **100 SAVE** from the user —
   [tx 0x0784f60f56aca72075d5b67b68528d6ba13ffff85141727dbe56bc8df8c44508](https://sepolia.basescan.org/tx/0x0784f60f56aca72075d5b67b68528d6ba13ffff85141727dbe56bc8df8c44508)
   (block 61160888, 5 blocks later).
4. On-chain state after the loop: `vault.saved(user) = 100 SAVE`,
   vault SAVE balance = 100, `RSC.totalSweepRequested(user) = 100`.

Explorers: [lasna.reactscan.net](https://lasna.reactscan.net) ·
[sepolia.basescan.org](https://sepolia.basescan.org)

Funding used (testnet only): 0.05 Sepolia ETH from the Google Cloud
faucet → bridged 0.049 ETH to Base Sepolia → swapped 0.015 ETH for
1.5 lREACT (rate 1 ETH = 100 lREACT) → deployed all three contracts,
funded the vault with 0.01 ETH and the RSC with 1 lREACT.

## Tests

`forge test` — 24 tests covering:

- Sweep math: 10% of 1,000 = 100; 100% works; sub-wei rounding rounds down
  (999 wei × 10% → 99 wei).
- No callback when: pct is 0, user unregistered, vault unset.
- `react()` routing: wrong topic0 / opCode / contract / chain are ignored
  without reverting; non-system callers are rejected.
- Access control: only the owner can set pct/vault (and pct ≤ 100).
- Callback auth: vault rejects non-proxy callers, wrong RSC address,
  zero amounts, and sweeps without allowance.
- Full loop end-to-end: Transfer log → callback payload → vault sweep.

## License

MIT — see [LICENSE](LICENSE).
