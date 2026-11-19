// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SaveToken
/// @notice Minimal ERC-20 used ONLY as the demo savings asset for Auto-Saver.
/// @dev Testnet-only test token. No real value. The owner (deployer) can mint
/// for demo setup; anyone can use `faucet()` to get 10,000 SAVE for trying
/// the demo. Total supply is capped at 10,000,000 SAVE.
contract SaveToken is ERC20, Ownable {
    /// @notice Amount minted by one `faucet()` call (10,000 SAVE, 18 decimals).
    uint256 public constant FAUCET_AMOUNT = 10_000 ether;

    /// @notice Hard cap on total supply (10,000,000 SAVE).
    uint256 public constant MAX_SUPPLY = 10_000_000 ether;

    constructor(address owner_) ERC20("SaveToken", "SAVE") Ownable(owner_) {}

    /// @notice Mint `amount` SAVE to `to`. Owner-only; used for demo setup.
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "SaveToken: supply cap");
        _mint(to, amount);
    }

    /// @notice Free demo faucet: mints FAUCET_AMOUNT SAVE to the caller.
    function faucet() external {
        require(totalSupply() + FAUCET_AMOUNT <= MAX_SUPPLY, "SaveToken: supply cap");
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
