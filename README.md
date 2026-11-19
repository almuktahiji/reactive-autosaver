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
./swap-lreact.sh  # 0.1 Base Sepolia ETH -> 10 lREACT (run first)
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

## Testnet addresses

| Contract | Chain | Address |
|---|---|---|
| SaveToken | Base Sepolia (84532) | _TBD after deploy_ |
| AutoSaverReactive | Lasna (5318007) | _TBD after deploy_ |
| AutoSaverVault | Base Sepolia (84532) | _TBD after deploy_ |

Explorers: [lasna.reactscan.net](https://lasna.reactscan.net) ·
[sepolia.basescan.org](https://sepolia.basescan.org)

Funding needed (testnet only): ~0.15 Base Sepolia ETH total — 0.1 ETH swaps
to 10 lREACT for the Lasna side, ~0.02 ETH for the Base deploys, ~0.03 ETH
to fund the vault's callback fees. Base Sepolia ETH comes from the faucet
(captcha): https://faucet.zalalena.com/base

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
