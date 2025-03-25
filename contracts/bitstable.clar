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

;; Initialize contract with key parameters
(define-public (initialize (oracle principal) (collector principal))
  (begin
    (asserts! (not (var-get initialized)) ERR-ALREADY-INITIALIZED)
    (var-set contract-owner tx-sender)
    (var-set oracle-address oracle)
    (var-set fee-collector collector)
    (var-set initialized true)
    (ok true)
  )
)

;; Governance functions

;; Update oracle address (callable by contract owner)
(define-public (set-oracle (new-oracle principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set oracle-address new-oracle)
    (ok true)
  )
)

;; Update fee collector (callable by contract owner)
(define-public (set-fee-collector (new-collector principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set fee-collector new-collector)
    (ok true)
  )
)

;; Emergency pause protocol (callable by contract owner)
(define-public (pause-protocol)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set protocol-paused true)
    (ok true)
  )
)

;; Resume protocol functionality (callable by contract owner)
(define-public (resume-protocol)
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set protocol-paused false)
    (ok true)
  )
)

;; Oracle functions

;; Update BTC/USD price (callable by oracle)
(define-public (update-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get oracle-address)) ERR-NOT-AUTHORIZED)
    (asserts! (> new-price u0) ERR-PRICE-INVALID)
    (var-set last-price-btc-usd new-price)
    (var-set last-price-update stacks-block-height)
    (ok true)
  )
)

;; Vault management functions

;; Create/add collateral to vault and mint BUSD
(define-public (deposit-collateral-and-borrow (collateral-amount uint) (busd-to-mint uint))
  (let (
    (sender tx-sender)
    (existing-vault (default-to 
      { collateral: u0, debt: u0, last-fee-timestamp: stacks-block-height } 
      (map-get? vaults sender)
    ))
    (new-collateral (+ (get collateral existing-vault) collateral-amount))
    (new-debt (+ (get debt existing-vault) busd-to-mint))
    (current-time stacks-block-height)
    (updated-debt (+ (get debt existing-vault) (calculate-accrued-fees sender)))
    (final-debt (+ updated-debt busd-to-mint))
  )
    (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> collateral-amount u0) ERR-ZERO-AMOUNT)
    (asserts! (>= new-collateral MINIMUM_COLLATERAL) ERR-BELOW-MINIMUM)
    (asserts! (or (>= busd-to-mint MINIMUM_DEBT) (is-eq busd-to-mint u0)) ERR-BELOW-MINIMUM)
    
    ;; Check if price is recent enough
    (asserts! (price-is-valid) ERR-PRICE-OUTDATED)
    
    ;; Check collateral ratio if minting BUSD
    (if (> busd-to-mint u0)
      (asserts! (is-collateral-ratio-valid new-collateral final-debt) ERR-INSUFFICIENT-COLLATERAL)
      true
    )
    
    ;; Transfer collateral from sender (would require sBTC or wrapped BTC contract integration)
    ;; For example: (try! (stx-transfer? collateral-amount sender (as-contract tx-sender)))
    ;; Using STX as placeholder for demonstration
    (try! (stx-transfer? collateral-amount sender (as-contract tx-sender)))
    
    ;; Mint BUSD if requested
    (if (> busd-to-mint u0)
      (try! (ft-mint? busd busd-to-mint sender))
      true
    )
    
    ;; Update vault and global state
    (map-set vaults sender {
      collateral: new-collateral,
      debt: final-debt,
      last-fee-timestamp: current-time
    })
    
    (var-set total-collateral (+ (var-get total-collateral) collateral-amount))
    (var-set total-debt (+ (var-get total-debt) busd-to-mint))
    
    (ok true)
  )
)