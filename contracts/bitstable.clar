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

;; Repay debt and withdraw collateral
(define-public (repay-and-withdraw (busd-to-repay uint) (collateral-to-withdraw uint))
  (let (
    (sender tx-sender)
    (existing-vault (default-to { collateral: u0, debt: u0, last-fee-timestamp: u0 } (map-get? vaults sender)))
    (accrued-fees (calculate-accrued-fees sender))
    (current-debt (+ (get debt existing-vault) accrued-fees))
    (new-debt (if (>= busd-to-repay current-debt) u0 (- current-debt busd-to-repay)))
    (new-collateral (- (get collateral existing-vault) collateral-to-withdraw))
    (current-time stacks-block-height)
  )
    (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (or (> busd-to-repay u0) (> collateral-to-withdraw u0)) ERR-ZERO-AMOUNT)
    (asserts! (<= collateral-to-withdraw (get collateral existing-vault)) ERR-INSUFFICIENT-COLLATERAL)
    (asserts! (<= busd-to-repay current-debt) ERR-TOO-MUCH-DEBT)
    
    ;; Check collateral ratio after withdrawal if debt remains
    (if (> new-debt u0)
      (begin
        (asserts! (price-is-valid) ERR-PRICE-OUTDATED)
        (asserts! (>= new-collateral MINIMUM_COLLATERAL) ERR-BELOW-MINIMUM)
        (asserts! (is-collateral-ratio-valid new-collateral new-debt) ERR-INSUFFICIENT-COLLATERAL)
      )
      true
    )
    
    ;; Burn BUSD from sender
    (if (> busd-to-repay u0)
      (try! (ft-burn? busd busd-to-repay sender))
      true
    )
    
    ;; Transfer collateral back to sender if withdrawing
    (if (> collateral-to-withdraw u0)
      ;; For example: (try! (as-contract (stx-transfer? collateral-to-withdraw tx-sender sender)))
      (try! (as-contract (stx-transfer? collateral-to-withdraw tx-sender sender)))
      true
    )
    
    ;; Update vault and global state
    (map-set vaults sender {
      collateral: new-collateral,
      debt: new-debt,
      last-fee-timestamp: current-time
    })
    
    (var-set total-collateral (- (var-get total-collateral) collateral-to-withdraw))
    (var-set total-debt (- (var-get total-debt) (if (>= busd-to-repay current-debt) current-debt busd-to-repay)))
    
    (ok true)
  )
)

;; Liquidate undercollateralized vault
(define-public (liquidate (vault-owner principal) (busd-amount uint))
  (let (
    (liquidator tx-sender)
    (vault (unwrap! (map-get? vaults vault-owner) ERR-VAULT-NOT-FOUND))
    (accrued-fees (calculate-accrued-fees vault-owner))
    (current-debt (+ (get debt vault) accrued-fees))
    (current-time stacks-block-height)
    (btc-price (var-get last-price-btc-usd))
    (collateral-ratio (get-collateral-ratio (get collateral vault) current-debt))
    (liquidation-amount (if (> busd-amount current-debt) current-debt busd-amount))
    (btc-equivalent (/ (* liquidation-amount DECIMAL_PRECISION) btc-price))
    (bonus-percentage (+ u100 LIQUIDATION_PENALTY)) ;; 110% (100% + 10% bonus)
    (btc-with-bonus (/ (* btc-equivalent bonus-percentage) u100))
    (final-collateral (- (get collateral vault) btc-with-bonus))
    (final-debt (- current-debt liquidation-amount))
  )
    (asserts! (var-get initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (price-is-valid) ERR-PRICE-OUTDATED)
    (asserts! (> busd-amount u0) ERR-ZERO-AMOUNT)
    
    ;; Check if the vault is actually liquidatable
    (asserts! (< collateral-ratio LIQUIDATION-THRESHOLD) ERR-NOT-LIQUIDATABLE)
    
    ;; Burn BUSD from liquidator
    (try! (ft-burn? busd liquidation-amount liquidator))
    
    ;; Transfer collateral to liquidator with bonus
    ;; For example: (try! (as-contract (stx-transfer? btc-with-bonus tx-sender liquidator)))
    (try! (as-contract (stx-transfer? btc-with-bonus tx-sender liquidator)))
    
    ;; Update vault state
    (if (is-eq final-debt u0)
      (map-delete vaults vault-owner)
      (map-set vaults vault-owner {
        collateral: final-collateral,
        debt: final-debt,
        last-fee-timestamp: current-time
      })
    )
    
    ;; Update global state
    (var-set total-collateral (- (var-get total-collateral) btc-with-bonus))
    (var-set total-debt (- (var-get total-debt) liquidation-amount))
    
    (ok true)
  )
)

;; Helper functions

;; Calculate stability fees accrued since last update
(define-private (calculate-accrued-fees (user principal))
  (let (
    (vault (default-to { collateral: u0, debt: u0, last-fee-timestamp: u0 } (map-get? vaults user)))
    (debt (get debt vault))
    (last-timestamp (get last-fee-timestamp vault))
    (current-time stacks-block-height)
    (time-elapsed (- current-time last-timestamp))
    (fee-rate (/ (* STABILITY_FEE time-elapsed) (* u365 u86400))) ;; Annual rate prorated for elapsed time
    (accrued-fee (/ (* debt fee-rate) u100))
  )
    (if (is-eq debt u0)
      u0
      accrued-fee
    )
  )
)

;; Check if price feed is valid (not too old)
(define-private (price-is-valid)
  (let (
    (current-time stacks-block-height)
    (last-update (var-get last-price-update))
    (time-elapsed (- current-time last-update))
  )
    (and (> (var-get last-price-btc-usd) u0) (<= time-elapsed PRICE_TIMEOUT))
  )
)

;; Check if collateral ratio is valid for a given amount of collateral and debt
(define-private (is-collateral-ratio-valid (collateral uint) (debt uint))
  (let (
    (ratio (get-collateral-ratio collateral debt))
  )
    (>= ratio MIN-COLLATERAL-RATIO)
  )
)

;; Calculate collateral ratio for a given amount of collateral and debt
(define-private (get-collateral-ratio (collateral uint) (debt uint))
  (let (
    (btc-price (var-get last-price-btc-usd))
    (collateral-value-usd (* collateral btc-price))
  )
    (if (is-eq debt u0)
      u0 ;; Return 0 to avoid division by zero
      (/ (* collateral-value-usd u100) (* debt DECIMAL_PRECISION))
    )
  )
)

;; Read-only functions

;; Get vault information
(define-read-only (get-vault (user principal))
  (map-get? vaults user)
)

;; Get current BTC price
(define-read-only (get-btc-price)
  {
    price: (var-get last-price-btc-usd),
    last-update: (var-get last-price-update)
  }
)

;; Get global stats
(define-read-only (get-global-stats)
  {
    total-collateral: (var-get total-collateral),
    total-debt: (var-get total-debt),
    btc-price: (var-get last-price-btc-usd),
    protocol-paused: (var-get protocol-paused)
  }
)

;; Get user's current collateral ratio
(define-read-only (get-user-collateral-ratio (user principal))
  (let (
    (vault (default-to { collateral: u0, debt: u0, last-fee-timestamp: u0 } (map-get? vaults user)))
    (accrued-fees (calculate-accrued-fees user))
    (current-debt (+ (get debt vault) accrued-fees))
  )
    (get-collateral-ratio (get collateral vault) current-debt)
  )
)

;; Check if a vault is liquidatable
(define-read-only (is-liquidatable (user principal))
  (let (
    (collateral-ratio (get-user-collateral-ratio user))
  )
    (< collateral-ratio LIQUIDATION-THRESHOLD)
  )
)

;; FT token meta functions for BUSD stablecoin

(define-public (transfer-busd (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (not (var-get protocol-paused)) ERR-NOT-AUTHORIZED)
    (ft-transfer? busd amount sender recipient)
  )
)

(define-read-only (get-name-busd)
  (ok "BitStable USD")
)

(define-read-only (get-symbol-busd)
  (ok "BUSD")
)

(define-read-only (get-decimals-busd)
  (ok u6)
)

(define-read-only (get-balance-busd (user principal))
  (ok (ft-get-balance busd user))
)

(define-read-only (get-total-supply-busd)
  (ok (ft-get-supply busd))
)

;; BST governance token functions

(define-public (transfer-bst (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (ft-transfer? bst amount sender recipient)
)

(define-read-only (get-name-bst)
  (ok "BitStable Governance Token")
)

(define-read-only (get-symbol-bst)
  (ok "BST")
)

(define-read-only (get-decimals-bst)
  (ok u6)
)

(define-read-only (get-balance-bst (user principal))
  (ok (ft-get-balance bst user))
)

(define-read-only (get-total-supply-bst)
  (ok (ft-get-supply bst))
)

;; Mint BST tokens (callable by contract owner)
(define-public (mint-bst (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ft-mint? bst amount recipient)
  )
)