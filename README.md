# SatoshiStable Protocol Documentation

## Overview

SatoshiStable is a decentralized finance protocol enabling Bitcoin holders to mint BUSD - a USD-pegged stablecoin - while maintaining custody of their BTC. Built on Stacks Layer 2, it combines Bitcoin's security with advanced DeFi capabilities through an over-collateralized debt position model.

## Key Features

- **BTC-Backed Stablecoins**: Mint BUSD using Bitcoin-denominated collateral
- **Autonomous Monetary Policy**:
  - 150% minimum collateral ratio
  - 130% liquidation threshold with 10% penalty
  - 1% annual stability fee
- **Non-Custodial Vaults**: Users retain control of collateral
- **Decentralized Governance**: BST token holders govern protocol parameters
- **Stacks L2 Integration**: Bitcoin-secured smart contracts with fast transactions

## Technical Specifications

### System Constants

| Parameter               | Value    | Description                             |
| ----------------------- | -------- | --------------------------------------- |
| `MIN-COLLATERAL-RATIO`  | 150%     | Minimum collateralization ratio         |
| `LIQUIDATION-THRESHOLD` | 130%     | Collateral ratio triggering liquidation |
| `LIQUIDATION_PENALTY`   | 10%      | Penalty applied during liquidation      |
| `STABILITY_FEE`         | 1%       | Annual fee on outstanding debt          |
| `MINIMUM_COLLATERAL`    | 0.1 BTC  | Minimum vault collateral amount         |
| `MINIMUM_DEBT`          | 100 BUSD | Minimum debt issuance                   |

### Core Components

1. **Vault Management System**

   - Collateralization ratio calculations
   - Debt accrual with stability fees
   - Automated liquidation mechanisms

2. **Price Oracle System**

   - Decentralized BTC/USD feed
   - 1-hour price freshness requirement

3. **Token System**
   - BUSD (Stablecoin)
   - BST (Governance Token)

## Smart Contract Functions

### Governance Functions

| Function            | Description                     | Access Control    |
| ------------------- | ------------------------------- | ----------------- |
| `initialize`        | Initializes protocol parameters | Contract deployer |
| `set-oracle`        | Updates price oracle address    | Contract owner    |
| `set-fee-collector` | Changes fee recipient           | Contract owner    |
| `pause-protocol`    | Emergency system pause          | Contract owner    |
| `resume-protocol`   | Resume normal operations        | Contract owner    |

### Oracle Functions

| Function       | Description                              |
| -------------- | ---------------------------------------- |
| `update-price` | Oracle updates BTC/USD price (micro USD) |

### Vault Operations

| Function                        | Parameters                              | Description                         |
| ------------------------------- | --------------------------------------- | ----------------------------------- |
| `deposit-collateral-and-borrow` | (collateral-amount, busd-to-mint)       | Create/adjust vault + mint BUSD     |
| `repay-and-withdraw`            | (busd-to-repay, collateral-to-withdraw) | Reduce debt + reclaim collateral    |
| `liquidate`                     | (vault-owner, busd-amount)              | Liquidate undercollateralized vault |

### Token Operations

**BUSD Stablecoin**

- `transfer-busd`: Transfer BUSD between accounts
- `get-balance-busd`: Check user balance
- `get-total-supply-busd`: Total BUSD minted

**BST Governance Token**

- `transfer-bst`: Transfer BST tokens
- `mint-bst`: Create new governance tokens (owner only)

## Risk Parameters

```clarity
;; Collateral Calculation Example
Collateral Ratio = (Collateral in BTC * BTC Price) / (Debt in BUSD) * 100

;; Liquidation Process
Liquidator receives: (Debt Repaid * (BTC Price^-1)) * 110%
Protocol collects: 10% penalty in BTC
```

## Error Codes

| Code | Error                       | Description                        |
| ---- | --------------------------- | ---------------------------------- |
| 100  | ERR-NOT-AUTHORIZED          | Unauthorized access attempt        |
| 101  | ERR-INSUFFICIENT-COLLATERAL | Below minimum collateral ratio     |
| 102  | ERR-VAULT-NOT-FOUND         | Specified vault does not exist     |
| 103  | ERR-PRICE-OUTDATED          | Stale price data (>1 hour old)     |
| 104  | ERR-BELOW-MINIMUM           | Operation below minimum threshold  |
| 105  | ERR-NOT-LIQUIDATABLE        | Vault not eligible for liquidation |

## Security Model

1. **Collateral Safeguards**

   - Over-collateralization requirement
   - Minimum vault size (0.1 BTC)
   - Time-weighted stability fees

2. **Price Feed Protections**

   - Oracle authentication
   - Price freshness checks
   - Decentralized oracle support

3. **System Controls**
   - Emergency pause functionality
   - Governance-controlled parameters
   - Non-custodial asset management

## Usage Examples

### Creating a Vault

```clarity
;; Deposit 0.5 BTC and mint 20,000 BUSD
(contract-call? .satoshistable deposit-collateral-and-borrow u500000000 u20000000)
```

### Repaying Debt

```clarity
;; Repay 5,000 BUSD and withdraw 0.1 BTC
(contract-call? .satoshistable repay-and-withdraw u5000000 u100000000)
```

### Liquidating a Vault

```clarity
;; Liquidate 10,000 BUSD of undercollateralized debt
(contract-call? .satoshistable liquidate 'vault-owner u10000000)
```

## Governance Framework

BST token holders can:

- Adjust fee structures
- Modify collateral ratios
- Upgrade system parameters
- Manage oracle integrations

Governance proposals require BST staking and majority approval through on-chain voting.

## Audit Considerations

1. Oracle reliability mechanisms
2. Interest accrual precision
3. Liquidation incentive alignment
4. Edge case handling for:
   - Price volatility scenarios
   - Simultaneous transactions
   - Network congestion events
