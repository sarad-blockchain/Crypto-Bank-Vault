# CryptoBankVault

> A non-custodial ETH vault with share-based accounting and ERC20 token rewards, built on Solidity ^0.8.34.

---

## About

CryptoBankVault is a smart contract that lets users deposit ETH and receive proportional vault shares in return. Over time, those shares accrue ERC20 token rewards based on how long the user has held them. The contract is designed with DeFi security best practices at its core: reentrancy protection, pause/unpause functionality, per-user deposit caps, and a safe emergency exit mechanism that works even when the vault is paused.

This project was built as part of my blockchain development portfolio to demonstrate proficiency in:

- Solidity smart contract architecture
- OpenZeppelin security primitives (`ReentrancyGuard`, `Pausable`, `Ownable`)
- ERC20 token integration and reward distribution logic
- Share-based vault accounting (inspired by ERC-4626)
- Checks-Effects-Interactions pattern to prevent reentrancy attacks
- On-chain access control and emergency protocols

---

## Features

| Feature | Description |
|---|---|
| **ETH Deposits** | Users deposit ETH and receive vault shares proportional to the pool |
| **ETH Withdrawals** | Redeem shares for the corresponding ETH amount |
| **ERC20 Rewards** | Earn reward tokens over time based on shares held |
| **Emergency Exit** | Instant full withdrawal available even when the vault is paused |
| **Owner Controls** | Pause/unpause, adjust reward rate, modify max balance per user |
| **Reentrancy Safe** | All state changes happen before external calls (CEI pattern) |

---

## Contract Overview

```
CryptoBankVault
├── depositEther()         — Deposit ETH, receive shares
├── withdrawEther(amount)  — Redeem shares for ETH
├── claimReward()          — Claim accrued ERC20 rewards
├── previewRewards(user)   — View pending rewards (read-only)
├── emergencyWithdraw()    — Exit immediately, no rewards
├── pause() / unpause()    — Owner-only circuit breaker
├── modifyMaxBalance()     — Update per-user ETH cap
└── setRewardRate()        — Update reward emission rate
```

---

## Tech Stack

- **Solidity** ^0.8.34
- **OpenZeppelin Contracts** — `ERC20`, `ReentrancyGuard`, `Pausable`, `Ownable`

---

## Security Considerations

- All functions that transfer ETH use the **Checks-Effects-Interactions** pattern
- `nonReentrant` modifier applied to all state-changing external functions
- `emergencyWithdraw` is accessible by any user (not just the owner), ensuring users can always exit
- `rewardRate` is scaled by `1e18` to avoid precision loss in integer arithmetic

---

## License

GPL-3.0-only
