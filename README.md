# 🪙 Foundry StableCoin 2025: Decentralized Stable Coin (DSC) Protocol

A robust, decentralized, and audited stablecoin protocol built entirely with the **Foundry** development toolchain.

This project implements a **Crypto-Collateralized Stablecoin** system, allowing users to deposit crypto assets (like WETH, WBTC) as collateral to mint the native stablecoin, the **Decentralized Stable Coin (DSC)**, which is soft-pegged to the US Dollar.

---

## 🎓 Project Credits

This project was developed as a guided exercise, and massive credit is due to the educators and communities who provided the foundation and instruction:

* **Cyfrin Updraft** (and the entire Cyfrin team)
* **Patrick Collins** (for providing exceptional, in-depth instruction on the topic)

---

## 🛣️ Future Work & Contribution Opportunities

This project is a work in progress. We welcome contributions from the community to enhance security, testing, and robustness in the following areas:

* **Complete Test Coverage:** While core logic is tested, coverage must be expanded:
    * Writing **more extensive unit and fuzz tests** for edge cases in liquidation and collateral handling.
    * Developing dedicated **oracle failure tests** to ensure the system gracefully handles stale or manipulated price feeds.
* **System Resiliency Logic:** Developing a contingency logic for **black swan events**. This includes:
    * Implementing a robust method to **pause the system** (emergency shutdown) if the collateral value suddenly crashes (e.g., 50% drop in minutes) to prevent catastrophic protocol insolvency.
    * Adding a **Global Settlement** mechanism to securely wind down the protocol if the peg fails irrevocably.
* **New Collateral Assets:** Integrating and testing support for additional collateral types (e.g., WBTC, LINK).
* **Decentralized Governance:** Implementing a voting or time-lock mechanism to safely manage system parameters (e.g., liquidation ratio, collateral limits) after deployment.


## 💡 The Stablecoin Explained

### What is a Stablecoin?

A stablecoin is a class of cryptocurrency designed to offer **price stability** by having its market value pegged to an external asset, most commonly the US Dollar. They serve as a critical bridge between volatile crypto assets and traditional fiat currencies, enabling fast, low-cost transfers without market risk.

### Types of Stablecoins

Stablecoins are generally categorized by the collateral mechanism they use:

1.  **Fiat-Backed:** Backed 1:1 by traditional fiat currency (USD, EUR) held in a bank account by a centralized issuer (e.g., **USDC**, **USDT**).
2.  **Commodity-Backed:** Backed by tangible assets like gold or real estate (e.g., **PAXG**).
3.  **Algorithmic:** No direct collateral; stability is maintained by smart contracts that automatically adjust the token supply based on market demand.
4.  **Crypto-Collateralized (Decentralized):** Backed by other volatile cryptocurrencies (like ETH) which are locked in smart contracts. They use **over-collateralization** to account for the volatility of the underlying asset.

### Our Stablecoin: Crypto-Collateralized (DAI Model)

This project, **Foundry StableCoin 2025**, creates a **Crypto-Collateralized** stablecoin known as the **Decentralized Stable Coin (DSC)**.

* **Mechanism:** Users deposit approved, high-value crypto (e.g., WETH) into a smart contract (`DSCEngine`). The collateral must be **over-collateralized** (e.g., $200 worth of ETH to mint $100 worth of DSC).
* **Solvency:** The system is secured by a **Liquidation Mechanism** that allows any user to liquidate a position if the collateral value drops below a minimum threshold, ensuring the system remains solvent.

---

## ⚙️ Core Developer Technologies & Logic

### Architecture Overview

The protocol is split into two primary, purpose-built contracts:

1.  **`DecentralizedStableCoin.sol` (DSC):** A simple, mintable/burnable **ERC-20 token** whose supply is exclusively controlled by the `DSCEngine` contract. It is the stablecoin itself.
2.  **`DSCEngine.sol`:** The core logic hub. It handles all critical functions:
    * **Collateral Deposit/Redeem:** Locking and unlocking collateral assets.
    * **Mint/Burn DSC:** Controlling the supply of DSC based on the value of the locked collateral.
    * **Health Factor Check:** Calculating a user's collateral ratio to ensure they are not under-collateralized.
    * **Liquidation:** Allowing protocol participants to close risky, under-collateralized positions.

### Decentralized Oracles: Chainlink Price Feeds

A decentralized stablecoin relies on accurate, real-time pricing for its collateral assets. We use **Chainlink Price Feeds** for this:

* **What it is:** Chainlink is a **Decentralized Oracle Network (DON)** that aggregates data from multiple high-quality, off-chain sources (exchanges, data providers).
* **How it Works Here:** The `DSCEngine` contract reads the price of collateral (e.g., `ETH/USD`) from the Chainlink Aggregator contract. This prevents manipulation, as the price is a median from many independent nodes, securing the liquidation logic.

---

## 🛠️ Project Dependencies

This project relies on battle-tested external libraries and the foundational **Foundry Standard Library** for testing.

### 1. `forge-std` (Foundry Standard Library)

This is the standard library used for all Foundry tests, providing the base `Test.sol` contract and the essential `Vm` (Virtual Machine) instance for cheat codes.

### 2. OpenZeppelin Contracts

OpenZeppelin is the gold standard for secure, community-audited contracts. We use them for:

| Contract | Purpose |
| :--- | :--- |
| `ERC20.sol` | Base implementation for the **DSC** token. |
| `Ownable.sol` | Securely manages administrative access (e.g., setting fees, pausing functions) for the `DSCEngine`. |
| `IERC20.sol` | Interfaces for interacting with collateral tokens (WETH, WBTC, etc.). |

### 3. Chainlink Contracts

Used to interface with the Decentralized Oracle Network:

| Contract | Purpose |
| :--- | :--- |
| `AggregatorV3Interface.sol` | The standard interface required to read the latest price data from a **Chainlink Price Feed**. |

---

## 🧪 Advanced Foundry Testing

This project leverages the advanced testing capabilities of Foundry to ensure code security and protocol robustness.

### Fuzz Testing (Fuzzing)

**Fuzzing** involves providing **random or semi-random inputs** to a function to see if the contract logic breaks or reverts under unexpected conditions.

* **Stateless Fuzzing:** Standard test functions that take inputs (e.g., `testMintDSC(uint256 amount)`) run thousands of times with random values to test edge cases (like zero, max uint256, etc.).

### Invariant Testing (Stateful Fuzzing)

**Invariant Testing** is a state-of-the-art security technique for DeFi protocols. An **Invariant** is a property that must *always* be true, regardless of the sequence of actions taken by users.

* **The Handler:** A special contract (`DSCEngineHandler.sol`) is created that exposes the critical public functions (`depositCollateral`, `mintDSC`, `liquidate`, etc.).
* **The Invariant Test:** The fuzzer calls random functions from the Handler in a random sequence for a set number of runs. After *every* single function call, the Invariant functions in the test file are executed to check if the protocol state is still secure.
* **Example Invariants:**
    1.  The total supply of DSC must **always** be less than the total dollar value of all collateral locked in the system.
    2.  The protocol must never hold more WETH than the collateral vault balance.

### Foundry Cheat Codes Used

Foundry provides "cheat codes" (`vm.*`) that allow you to manipulate the EVM state for comprehensive testing in the local Anvil environment:

| Cheat Code | Purpose in Testing |
| :--- | :--- |
| `vm.prank(address)` | Sets the `msg.sender` for the **next** function call, simulating a user. |
| `vm.deal(address, uint256)` | Sets the **Ether balance** of an address, simulating a user having funds. |
| `vm.startPrank/vm.stopPrank` | Sets the `msg.sender` for **multiple subsequent** calls (a sequence of actions). |
| `vm.expectRevert()` | Asserts that the next transaction **must revert**, used to test failure conditions. |
| `vm.expectEmit(...)` | Asserts that a specific **event** is emitted during a transaction. |
| `vm.roll(uint256)` | Manually sets the `block.number`, useful for time-dependent logic. |
| `vm.warp(uint256)` | Manually sets the `block.timestamp`, crucial for testing time-locks or oracle freshness. |
| `vm.label(address, string)` | Assigns a name to an address for cleaner trace output. |

---

## 📦 Installation & Usage

### Prerequisites

* **Foundry:** Install via `curl -L https://foundry.paradigm.xyz | bash` and run `foundryup`.
* **Git:** Required for cloning.

### Setup

```bash
# Clone the repository
git clone [https://github.com/PikachuBoss69/Foundry-StableCoin-2025.git](https://github.com/PikachuBoss69/Foundry-StableCoin-2025.git)
cd Foundry-StableCoin-2025

# Install dependencies (submodules)
forge update

# Compile the contracts
forge build