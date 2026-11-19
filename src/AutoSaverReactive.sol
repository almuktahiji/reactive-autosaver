// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title AutoSaverReactive
/// @notice Reactive contract (Lasna) for the Auto-Saver demo.
///
/// Every time SAVE moves on Base Sepolia, this contract checks whether the
/// *recipient* registered a savings percentage. If they did, it asks the
/// Reactive system contract to call `sweep()` on the AutoSaverVault
/// (Base Sepolia), which pulls that percentage of the received amount into
/// the user's vault balance. Set it once, forget it — saving happens
/// automatically on every incoming transfer.
///
/// Flow:
///   SaveToken Transfer (Base Sepolia)
///     -> react() here (Lasna, via subscription)
///     -> requestCallbackV_1_0 -> AutoSaverVault.sweep() (Base Sepolia)
///     -> vault pulls sweep amount from the user via transferFrom
///
/// @dev Testnet-only (Lasna + Base Sepolia). No mainnet, no real funds.
contract AutoSaverReactive is AbstractReactive, Ownable {
    /// @notice Chain id of the origin/destination network (Base Sepolia).
    uint256 public constant ORIGIN_CHAIN_ID = 84532;

    /// @notice Topic0 of ERC-20 Transfer(address,address,uint256).
    uint256 public constant TRANSFER_TOPIC0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @notice Gas limit requested for the vault callback (min allowed: 100,000).
    uint64 public constant CALLBACK_GAS_LIMIT = 400_000;

    /// @notice The token whose transfers trigger auto-saving.
    address public immutable token;

    /// @notice The vault on Base Sepolia that receives the swept funds.
    address public vault;

    /// @notice Savings percentage per user (0-100). 0 = not registered.
    mapping(address => uint256) public savingsPct;

    /// @notice Total sweep amount ever requested per user (for the demo UI).
    mapping(address => uint256) public totalSweepRequested;

    /// @notice Emitted when a user's savings percentage is set.
    event SavingsPctSet(address indexed user, uint256 pct);

    /// @notice Emitted when the vault address is set.
    event VaultSet(address indexed vault);

    /// @notice Emitted when a sweep callback is requested for a transfer.
    event SweepRequested(address indexed user, uint256 transferAmount, uint256 sweepAmount);

    /// @param token_ Address of SaveToken on Base Sepolia.
    /// @param owner_ Owner (deployer) — the only account that can register
    /// users and set the vault.
    constructor(address token_, address owner_) payable Ownable(owner_) {
        require(token_ != address(0), "AutoSaverReactive: zero token");
        token = token_;
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID,
            token_,
            TRANSFER_TOPIC0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Register (or update) a user's savings percentage, 0-100.
    /// @dev 0 unregisters the user (no sweeps). Owner-only.
    function setSavingsPct(address user, uint256 pct) external onlyOwner {
        require(user != address(0), "AutoSaverReactive: zero user");
        require(pct <= 100, "AutoSaverReactive: pct > 100");
        savingsPct[user] = pct;
        emit SavingsPctSet(user, pct);
    }

    /// @notice Set the vault contract on Base Sepolia. Owner-only.
    function setVault(address vault_) external onlyOwner {
        require(vault_ != address(0), "AutoSaverReactive: zero vault");
        vault = vault_;
        emit VaultSet(vault_);
    }

    /// @inheritdoc IReactive
    /// @dev Non-matching logs fall through silently — never revert as a
    /// filter (a revert still gets billed by the system contract).
    function react(LogRecord memory log_) external override onlySystem {
        if (
            log_.chainId != ORIGIN_CHAIN_ID ||
            log_.contractAddress != token ||
            log_.topic0 != TRANSFER_TOPIC0 ||
            log_.opCode != 3
        ) {
            return;
        }

        uint256 amount = abi.decode(log_.data, (uint256));
        // ERC-20 Transfer is a LOG3: topic1 = from, topic2 = to.
        address to = address(uint160(log_.topic2));

        uint256 pct = savingsPct[to];
        if (pct == 0) {
            return;
        }
        uint256 sweepAmount = (amount * pct) / 100;
        if (sweepAmount == 0 || vault == address(0)) {
            return;
        }

        totalSweepRequested[to] += sweepAmount;
        emit SweepRequested(to, amount, sweepAmount);

        // The callback proxy overwrites the first 160 bits of the payload
        // with this contract's address, so pass address(0) as a placeholder
        // for the `reactive_` argument of sweep().
        bytes memory payload = abi.encodeWithSignature(
            "sweep(address,address,uint256)",
            address(0),
            to,
            sweepAmount
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: ORIGIN_CHAIN_ID,
                recipient: vault,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    /// @dev Open to anyone (per Reactive docs): a third party can fund the
    /// contract and restart it. The balance is only ever used for fees.
    function coverDebt() external {
        _coverDebt();
    }

    // Note: `receive()` is inherited from AbstractPayer (payable) — the
    // contract accepts lREACT funding directly, no override needed.
}
