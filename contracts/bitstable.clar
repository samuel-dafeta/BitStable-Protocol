;; Title:
;; SatoshiStable: Bitcoin-Backed Stablecoin Protocol on Stacks L2
;; 
;; Summary:
;; Non-custodial DeFi protocol enabling BTC-collateralized stablecoin issuance with autonomous monetary policy,
;; combining Bitcoin's security with Stacks L2 smart contract capabilities.
;;
;; Description:
;; SatoshiStable is a decentralized finance primitive that allows users to lock Bitcoin-denominated collateral
;; (via Stacks L2 assets) to mint BUSD - a price-stable currency soft-pegged to the US Dollar. The protocol
;; implements an over-collateralized debt position model with:
;; - Real-time BTC price feeds from decentralized oracles
;; - Risk-managed vaults with 150% minimum collateral ratio
;; - Automated liquidations protected by 130% safety threshold
;; - Stability fee accrual mechanism (1% annual)
;; - Governance through native BST tokens
;;
;; Built natively on Bitcoin via Stacks layer-2, SatoshiStable combines Bitcoin's unmatched security with
;; advanced DeFi capabilities, offering a compliant framework for BTC holders to access stable liquidity
;; without selling their bitcoin positions. The protocol features non-custodial vault management,
;;

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u101))
(define-constant ERR-VAULT-NOT-FOUND (err u102))
(define-constant ERR-PRICE-OUTDATED (err u103))
(define-constant ERR-BELOW-MINIMUM (err u104))
(define-constant ERR-NOT-LIQUIDATABLE (err u105))
(define-constant ERR-TOO-MUCH-DEBT (err u106))
(define-constant ERR-ZERO-AMOUNT (err u107))
(define-constant ERR-ALREADY-INITIALIZED (err u108))
(define-constant ERR-NOT-INITIALIZED (err u109))
(define-constant ERR-PRICE-INVALID (err u110))

;; Constants
(define-constant MIN-COLLATERAL-RATIO u150) ;; 150% minimum collateral ratio (represented as percentage)
(define-constant LIQUIDATION-THRESHOLD u130) ;; 130% liquidation threshold
(define-constant LIQUIDATION_PENALTY u10) ;; 10% penalty on liquidation
(define-constant STABILITY_FEE u1) ;; 1% annual stability fee
(define-constant MINIMUM_COLLATERAL u10000000) ;; Minimum 0.1 BTC in microBTC (10^8 satoshis = 1 BTC)
(define-constant MINIMUM_DEBT u100000) ;; Minimum 100 BUSD in micro units
(define-constant PRICE_TIMEOUT u3600) ;; Price feed timeout in seconds (1 hour)
(define-constant DECIMAL_PRECISION u1000000) ;; For fixed-point arithmetic (6 decimals)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var oracle-address principal tx-sender)
(define-data-var last-price-btc-usd uint u0) ;; BTC/USD price in micro units
(define-data-var last-price-update uint u0) ;; Last price update timestamp
(define-data-var total-collateral uint u0) ;; Total BTC collateral in system (micro BTC)
(define-data-var total-debt uint u0) ;; Total BUSD debt in system (micro BUSD)
(define-data-var fee-collector principal tx-sender) ;; Address collecting fees
(define-data-var protocol-paused bool false) ;; Emergency pause switch
(define-data-var initialized bool false) ;; Initialization check

;; FT definitions for BUSD token and BST governance token
(define-fungible-token busd)
(define-fungible-token bst)

;; Vault structure to track user collateral and debt
(define-map vaults 
  principal
  {
    collateral: uint, ;; Collateral amount in micro BTC
    debt: uint,       ;; Debt amount in micro BUSD
    last-fee-timestamp: uint  ;; Last time stability fee was calculated
  }
)