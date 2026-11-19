// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AutoSaverVault
/// @notice Callback contract on Base Sepolia that holds users' auto-saved funds.
///
/// The Reactive Network calls `sweep()` here whenever a registered user
/// receives SAVE. The vault pulls the sweep amount from the user with
/// `transferFrom` — so each user approves the vault once (in the demo
/// frontend) and never has to think about saving again.
///
/// @dev Authenticates callbacks with BOTH guards, as the Reactive docs
/// require: `onlyServiceProvider` (caller must be the Base Sepolia callback
/// proxy) and `onlyCallbackSender` (first payload arg must be the RSC).
/// Testnet-only (Base Sepolia). No mainnet, no real funds.
contract AutoSaverVault is AbstractCallback {
    using SafeERC20 for IERC20;

    /// @notice The token being saved (SaveToken on Base Sepolia).
    IERC20 public immutable token;

    /// @notice Total SAVE swept into the vault per user.
    mapping(address => uint256) public saved;

    /// @notice Total SAVE ever swept into the vault.
    uint256 public totalSaved;

    /// @notice Emitted whenever a sweep lands in the vault.
    event Saved(address indexed user, uint256 amount);

    /// @param token_ Address of SaveToken on Base Sepolia.
    /// @param callbackProxy_ Base Sepolia callback proxy:
    /// 0x476F44b11F5C942c58f4c8E3d0300E5710743585
    /// @param callbackSender_ Address of the AutoSaverReactive contract (Lasna).
    constructor(address token_, IPayable callbackProxy_, address callbackSender_)
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        require(token_ != address(0), "AutoSaverVault: zero token");
        require(callbackSender_ != address(0), "AutoSaverVault: zero sender");
        token = IERC20(token_);
    }

    /// @notice Pull `amount` SAVE from `user` into the vault.
    /// @param reactive_ First payload arg — overwritten by the callback proxy
    /// with the RSC address; must equal the registered callback sender.
    /// @dev Called by the Base Sepolia callback proxy only. The user must
    /// have approved this vault for at least `amount` SAVE beforehand.
    function sweep(address reactive_, address user, uint256 amount)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        require(amount > 0, "AutoSaverVault: zero amount");
        token.safeTransferFrom(user, address(this), amount);
        saved[user] += amount;
        totalSaved += amount;
        emit Saved(user, amount);
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    /// @dev Open to anyone (per Reactive docs). The balance is only ever
    /// used to pay callback fees.
    function coverDebt() external {
        _coverDebt();
    }

    // Note: `receive()` is inherited from AbstractPayer (payable) — the
    // vault accepts Base Sepolia ETH funding directly, no override needed.
}
