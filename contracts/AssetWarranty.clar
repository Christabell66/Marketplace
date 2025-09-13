;; Digital Asset Warranty & Insurance System
;; Provides warranty coverage and insurance options for digital marketplace items

;; Error constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-NOT-OWNER (err u403))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-CLAIM (err u420))
(define-constant ERR-EXPIRED-WARRANTY (err u421))
(define-constant ERR-INSUFFICIENT-POOL (err u422))
(define-constant ERR-ALREADY-CLAIMED (err u423))
(define-constant ERR-INVALID-PARAMETERS (err u400))

;; Warranty types
(define-map warranty-templates
    { template-id: uint }
    {
        name: (string-ascii 50),
        duration-blocks: uint,
        coverage-percentage: uint,
        premium-rate: uint,
        creator: principal,
        active: bool
    }
)

;; Individual warranty policies
(define-map warranty-policies
    { policy-id: uint }
    {
        item-id: uint,
        template-id: uint,
        buyer: principal,
        seller: principal,
        purchase-price: uint,
        premium-paid: uint,
        start-height: uint,
        end-height: uint,
        status: (string-ascii 20),
        max-coverage: uint
    }
)

;; Insurance claims
(define-map warranty-claims
    { claim-id: uint }
    {
        policy-id: uint,
        claimant: principal,
        claim-amount: uint,
        claim-reason: (string-ascii 100),
        evidence-hash: (string-ascii 64),
        filed-at: uint,
        status: (string-ascii 20),
        approved-amount: uint,
        processed-by: (optional principal)
    }
)

;; Insurance pool for claims payouts
(define-map insurance-pools
    { pool-id: uint }
    {
        total-deposits: uint,
        total-claims-paid: uint,
        active-policies: uint,
        pool-manager: principal,
        created-at: uint
    }
)

;; Track provider performance and reputation
(define-map warranty-providers
    { provider: principal }
    {
        total-policies-issued: uint,
        total-claims-processed: uint,
        total-payouts: uint,
        reputation-score: uint,
        active-since: uint,
        verified: bool
    }
)

;; Policy premium calculations based on risk factors
(define-map risk-assessments
    { item-id: uint }
    {
        category-risk: uint,
        seller-risk: uint,
        price-risk: uint,
        calculated-premium: uint,
        assessment-date: uint,
        assessor: principal
    }
)

;; Data variables
(define-data-var next-template-id uint u1)
(define-data-var next-policy-id uint u1)
(define-data-var next-claim-id uint u1)
(define-data-var next-pool-id uint u1)
(define-data-var warranty-admin principal tx-sender)
(define-data-var default-pool-id uint u1)
(define-data-var base-premium-rate uint u5) ;; 5% base rate

;; Initialize default insurance pool
(map-set insurance-pools 
    { pool-id: u1 }
    {
        total-deposits: u0,
        total-claims-paid: u0,
        active-policies: u0,
        pool-manager: tx-sender,
        created-at: stacks-block-height
    }
)

;; Create warranty template
(define-public (create-warranty-template 
    (name (string-ascii 50))
    (duration-blocks uint)
    (coverage-percentage uint)
    (premium-rate uint))
    (let
        ((template-id (var-get next-template-id)))
        (asserts! (<= coverage-percentage u100) ERR-INVALID-PARAMETERS)
        (asserts! (<= premium-rate u50) ERR-INVALID-PARAMETERS)
        (asserts! (> duration-blocks u0) ERR-INVALID-PARAMETERS)
        (map-set warranty-templates
            { template-id: template-id }
            {
                name: name,
                duration-blocks: duration-blocks,
                coverage-percentage: coverage-percentage,
                premium-rate: premium-rate,
                creator: tx-sender,
                active: true
            }
        )
        (var-set next-template-id (+ template-id u1))
        (ok template-id)
    )
)

;; Purchase warranty for an item
(define-public (purchase-warranty 
    (item-id uint)
    (template-id uint)
    (purchase-price uint))
    (let
        ((template (unwrap! (map-get? warranty-templates { template-id: template-id }) ERR-NOT-FOUND))
         (policy-id (var-get next-policy-id))
         (premium-amount (/ (* purchase-price (get premium-rate template)) u100))
         (max-coverage (/ (* purchase-price (get coverage-percentage template)) u100))
         (end-height (+ stacks-block-height (get duration-blocks template))))
        (asserts! (get active template) ERR-INVALID-PARAMETERS)
        (try! (stx-transfer? premium-amount tx-sender (as-contract tx-sender)))
        (map-set warranty-policies
            { policy-id: policy-id }
            {
                item-id: item-id,
                template-id: template-id,
                buyer: tx-sender,
                seller: tx-sender, ;; Will be updated when integrated with marketplace
                purchase-price: purchase-price,
                premium-paid: premium-amount,
                start-height: stacks-block-height,
                end-height: end-height,
                status: "active",
                max-coverage: max-coverage
            }
        )
        (try! (update-insurance-pool-stats (var-get default-pool-id) premium-amount true))
        (unwrap-panic (update-provider-stats tx-sender true u0))
        (var-set next-policy-id (+ policy-id u1))
        (ok policy-id)
    )
)

;; File warranty claim
(define-public (file-warranty-claim 
    (policy-id uint)
    (claim-amount uint)
    (claim-reason (string-ascii 100))
    (evidence-hash (string-ascii 64)))
    (let
        ((policy (unwrap! (map-get? warranty-policies { policy-id: policy-id }) ERR-NOT-FOUND))
         (claim-id (var-get next-claim-id)))
        (asserts! (is-eq tx-sender (get buyer policy)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status policy) "active") ERR-INVALID-CLAIM)
        (asserts! (<= stacks-block-height (get end-height policy)) ERR-EXPIRED-WARRANTY)
        (asserts! (<= claim-amount (get max-coverage policy)) ERR-INVALID-CLAIM)
        (map-set warranty-claims
            { claim-id: claim-id }
            {
                policy-id: policy-id,
                claimant: tx-sender,
                claim-amount: claim-amount,
                claim-reason: claim-reason,
                evidence-hash: evidence-hash,
                filed-at: stacks-block-height,
                status: "pending",
                approved-amount: u0,
                processed-by: none
            }
        )
        (var-set next-claim-id (+ claim-id u1))
        (ok claim-id)
    )
)

;; Process warranty claim (admin function)
(define-public (process-warranty-claim 
    (claim-id uint)
    (approved bool)
    (approved-amount uint))
    (let
        ((claim (unwrap! (map-get? warranty-claims { claim-id: claim-id }) ERR-NOT-FOUND))
         (policy-id (get policy-id claim))
         (policy (unwrap! (map-get? warranty-policies { policy-id: policy-id }) ERR-NOT-FOUND))
         (claimant (get claimant claim)))
        (asserts! (is-eq tx-sender (var-get warranty-admin)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status claim) "pending") ERR-ALREADY-CLAIMED)
        (if approved
            (begin
                (asserts! (<= approved-amount (get claim-amount claim)) ERR-INVALID-PARAMETERS)
                (try! (as-contract (stx-transfer? approved-amount tx-sender claimant)))
                (try! (update-insurance-pool-stats (var-get default-pool-id) u0 false))
                (unwrap-panic (update-provider-stats (get seller policy) false approved-amount))
                (map-set warranty-claims
                    { claim-id: claim-id }
                    (merge claim {
                        status: "approved",
                        approved-amount: approved-amount,
                        processed-by: (some tx-sender)
                    })
                )
                (map-set warranty-policies
                    { policy-id: policy-id }
                    (merge policy { status: "claimed" })
                )
            )
            (map-set warranty-claims
                { claim-id: claim-id }
                (merge claim {
                    status: "rejected",
                    processed-by: (some tx-sender)
                })
            )
        )
        (ok true)
    )
)

;; Deposit funds into insurance pool
(define-public (contribute-to-insurance-pool (pool-id uint) (amount uint))
    (let
        ((pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) ERR-NOT-FOUND)))
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set insurance-pools
            { pool-id: pool-id }
            (merge pool { total-deposits: (+ (get total-deposits pool) amount) })
        )
        (ok true)
    )
)

;; Calculate risk-based premium
(define-public (assess-item-risk 
    (item-id uint)
    (category-risk uint)
    (seller-risk uint)
    (item-price uint))
    (let
        ((price-risk (if (> item-price u10000) u3 (if (> item-price u1000) u2 u1)))
         (total-risk-factor (+ category-risk (+ seller-risk price-risk)))
         (calculated-premium (/ (* (var-get base-premium-rate) total-risk-factor) u3)))
        (asserts! (is-eq tx-sender (var-get warranty-admin)) ERR-UNAUTHORIZED)
        (map-set risk-assessments
            { item-id: item-id }
            {
                category-risk: category-risk,
                seller-risk: seller-risk,
                price-risk: price-risk,
                calculated-premium: calculated-premium,
                assessment-date: stacks-block-height,
                assessor: tx-sender
            }
        )
        (ok calculated-premium)
    )
)

;; Update insurance pool statistics
(define-private (update-insurance-pool-stats (pool-id uint) (amount uint) (is-premium bool))
    (let
        ((pool (unwrap! (map-get? insurance-pools { pool-id: pool-id }) ERR-NOT-FOUND)))
        (if is-premium
            (map-set insurance-pools
                { pool-id: pool-id }
                (merge pool { 
                    total-deposits: (+ (get total-deposits pool) amount),
                    active-policies: (+ (get active-policies pool) u1)
                })
            )
            (map-set insurance-pools
                { pool-id: pool-id }
                (merge pool { 
                    total-claims-paid: (+ (get total-claims-paid pool) amount),
                    active-policies: (- (get active-policies pool) u1)
                })
            )
        )
        (ok true)
    )
)

;; Update provider statistics
(define-private (update-provider-stats (provider principal) (new-policy bool) (payout-amount uint))
    (let
        ((current-stats (default-to 
            { total-policies-issued: u0, total-claims-processed: u0, total-payouts: u0, 
              reputation-score: u100, active-since: stacks-block-height, verified: false }
            (map-get? warranty-providers { provider: provider }))))
        (if new-policy
            (map-set warranty-providers
                { provider: provider }
                (merge current-stats { 
                    total-policies-issued: (+ (get total-policies-issued current-stats) u1)
                })
            )
            (map-set warranty-providers
                { provider: provider }
                (merge current-stats { 
                    total-claims-processed: (+ (get total-claims-processed current-stats) u1),
                    total-payouts: (+ (get total-payouts current-stats) payout-amount)
                })
            )
        )
        (ok true)
    )
)

;; Verify warranty provider
(define-public (verify-warranty-provider (provider principal))
    (let
        ((provider-stats (unwrap! (map-get? warranty-providers { provider: provider }) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get warranty-admin)) ERR-UNAUTHORIZED)
        (map-set warranty-providers
            { provider: provider }
            (merge provider-stats { verified: true })
        )
        (ok true)
    )
)

;; Set warranty admin
(define-public (set-warranty-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get warranty-admin)) ERR-UNAUTHORIZED)
        (var-set warranty-admin new-admin)
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-warranty-template (template-id uint))
    (map-get? warranty-templates { template-id: template-id })
)

(define-read-only (get-warranty-policy (policy-id uint))
    (map-get? warranty-policies { policy-id: policy-id })
)

(define-read-only (get-warranty-claim (claim-id uint))
    (map-get? warranty-claims { claim-id: claim-id })
)

(define-read-only (get-insurance-pool (pool-id uint))
    (map-get? insurance-pools { pool-id: pool-id })
)

(define-read-only (get-provider-stats (provider principal))
    (map-get? warranty-providers { provider: provider })
)

(define-read-only (get-risk-assessment (item-id uint))
    (map-get? risk-assessments { item-id: item-id })
)

(define-read-only (is-warranty-active (policy-id uint))
    (match (map-get? warranty-policies { policy-id: policy-id })
        policy (and 
            (is-eq (get status policy) "active")
            (<= stacks-block-height (get end-height policy))
        )
        false
    )
)

(define-read-only (get-warranty-coverage (policy-id uint))
    (match (map-get? warranty-policies { policy-id: policy-id })
        policy (get max-coverage policy)
        u0
    )
)

(define-read-only (get-pool-solvency (pool-id uint))
    (match (map-get? insurance-pools { pool-id: pool-id })
        pool (- (get total-deposits pool) (get total-claims-paid pool))
        u0
    )
)
