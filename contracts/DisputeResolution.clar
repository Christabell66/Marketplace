;; Dispute Resolution & Mediation System
;; Provides structured dispute resolution for marketplace transactions
;; Includes mediator network, evidence submission, and resolution voting

;; Error constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-NOT-AUTHORIZED (err u403))
(define-constant ERR-INVALID-DISPUTE (err u420))
(define-constant ERR-DISPUTE-CLOSED (err u421))
(define-constant ERR-INSUFFICIENT-MEDIATORS (err u422))
(define-constant ERR-ALREADY-VOTED (err u423))
(define-constant ERR-NOT-MEDIATOR (err u424))
(define-constant ERR-INVALID-PARAMETERS (err u400))
(define-constant ERR-INSUFFICIENT-STAKE (err u425))
(define-constant ERR-DISPUTE-ACTIVE (err u426))

;; Dispute status constants
(define-constant STATUS-FILED "filed")
(define-constant STATUS-ASSIGNED "assigned") 
(define-constant STATUS-EVIDENCE "evidence")
(define-constant STATUS-VOTING "voting")
(define-constant STATUS-RESOLVED "resolved")
(define-constant STATUS-CLOSED "closed")

;; Dispute outcomes
(define-constant OUTCOME-BUYER-FAVOR "buyer-favor")
(define-constant OUTCOME-SELLER-FAVOR "seller-favor")
(define-constant OUTCOME-PARTIAL-REFUND "partial-refund")
(define-constant OUTCOME-NO-RESOLUTION "no-resolution")

;; Core dispute information
(define-map disputes
    { dispute-id: uint }
    {
        item-id: uint,
        buyer: principal,
        seller: principal,
        dispute-type: (string-ascii 30),
        dispute-reason: (string-ascii 200),
        transaction-amount: uint,
        dispute-fee: uint,
        filed-at: uint,
        status: (string-ascii 20),
        outcome: (optional (string-ascii 20)),
        refund-amount: uint,
        assigned-mediators: (list 3 principal),
        resolution-deadline: uint
    }
)

;; Evidence submitted by parties
(define-map dispute-evidence
    { dispute-id: uint, evidence-id: uint }
    {
        submitter: principal,
        evidence-type: (string-ascii 20),
        evidence-hash: (string-ascii 64),
        description: (string-ascii 100),
        submitted-at: uint
    }
)

;; Mediator registration and stats
(define-map mediators
    { mediator: principal }
    {
        stake-amount: uint,
        disputes-handled: uint,
        successful-resolutions: uint,
        reputation-score: uint,
        active: bool,
        registered-at: uint,
        specialties: (list 5 (string-ascii 20))
    }
)

;; Mediator votes on disputes
(define-map mediator-votes
    { dispute-id: uint, mediator: principal }
    {
        outcome: (string-ascii 20),
        refund-percentage: uint,
        reasoning: (string-ascii 150),
        voted-at: uint
    }
)

;; Track voting progress
(define-map voting-tallies
    { dispute-id: uint }
    {
        buyer-favor-votes: uint,
        seller-favor-votes: uint,
        partial-refund-votes: uint,
        no-resolution-votes: uint,
        total-votes: uint,
        average-refund-percentage: uint
    }
)

;; System configuration
(define-data-var next-dispute-id uint u1)
(define-data-var next-evidence-id uint u1)
(define-data-var dispute-admin principal tx-sender)
(define-data-var base-dispute-fee uint u50) ;; 50 STX base fee
(define-data-var mediator-min-stake uint u1000) ;; 1000 STX minimum stake
(define-data-var resolution-time-limit uint u1440) ;; ~10 days in blocks
(define-data-var mediator-reward-percentage uint u30) ;; 30% of dispute fee goes to mediators

;; File a new dispute
(define-public (file-dispute
    (item-id uint)
    (seller principal)
    (dispute-type (string-ascii 30))
    (dispute-reason (string-ascii 200))
    (transaction-amount uint))
    (let
        ((dispute-id (var-get next-dispute-id))
         (dispute-fee (calculate-dispute-fee transaction-amount)))
        (asserts! (> transaction-amount u0) ERR-INVALID-PARAMETERS)
        (try! (stx-transfer? dispute-fee tx-sender (as-contract tx-sender)))
        (map-set disputes
            { dispute-id: dispute-id }
            {
                item-id: item-id,
                buyer: tx-sender,
                seller: seller,
                dispute-type: dispute-type,
                dispute-reason: dispute-reason,
                transaction-amount: transaction-amount,
                dispute-fee: dispute-fee,
                filed-at: stacks-block-height,
                status: STATUS-FILED,
                outcome: none,
                refund-amount: u0,
                assigned-mediators: (list),
                resolution-deadline: (+ stacks-block-height (var-get resolution-time-limit))
            }
        )
        (var-set next-dispute-id (+ dispute-id u1))
        (ok dispute-id)
    )
)

;; Register as a mediator
(define-public (register-mediator 
    (stake-amount uint)
    (specialties (list 5 (string-ascii 20))))
    (begin
        (asserts! (>= stake-amount (var-get mediator-min-stake)) ERR-INSUFFICIENT-STAKE)
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        (map-set mediators
            { mediator: tx-sender }
            {
                stake-amount: stake-amount,
                disputes-handled: u0,
                successful-resolutions: u0,
                reputation-score: u100,
                active: true,
                registered-at: stacks-block-height,
                specialties: specialties
            }
        )
        (ok true)
    )
)

;; Assign mediators to a dispute (admin function)
(define-public (assign-mediators 
    (dispute-id uint)
    (mediator-list (list 3 principal)))
    (let
        ((dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get dispute-admin)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status dispute) STATUS-FILED) ERR-DISPUTE-ACTIVE)
        (asserts! (>= (len mediator-list) u1) ERR-INSUFFICIENT-MEDIATORS)
        (try! (validate-mediator-list mediator-list))
        (map-set disputes
            { dispute-id: dispute-id }
            (merge dispute {
                status: STATUS-ASSIGNED,
                assigned-mediators: mediator-list
            })
        )
        (map-set voting-tallies
            { dispute-id: dispute-id }
            {
                buyer-favor-votes: u0,
                seller-favor-votes: u0,
                partial-refund-votes: u0,
                no-resolution-votes: u0,
                total-votes: u0,
                average-refund-percentage: u0
            }
        )
        (ok true)
    )
)

;; Submit evidence for a dispute
(define-public (submit-evidence
    (dispute-id uint)
    (evidence-type (string-ascii 20))
    (evidence-hash (string-ascii 64))
    (description (string-ascii 100)))
    (let
        ((dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-NOT-FOUND))
         (evidence-id (var-get next-evidence-id)))
        (asserts! (or (is-eq tx-sender (get buyer dispute)) 
                     (is-eq tx-sender (get seller dispute))) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq (get status dispute) STATUS-CLOSED)) ERR-DISPUTE-CLOSED)
        (map-set dispute-evidence
            { dispute-id: dispute-id, evidence-id: evidence-id }
            {
                submitter: tx-sender,
                evidence-type: evidence-type,
                evidence-hash: evidence-hash,
                description: description,
                submitted-at: stacks-block-height
            }
        )
        (var-set next-evidence-id (+ evidence-id u1))
        (if (is-eq (get status dispute) STATUS-ASSIGNED)
            (map-set disputes
                { dispute-id: dispute-id }
                (merge dispute { status: STATUS-EVIDENCE })
            )
            true
        )
        (ok evidence-id)
    )
)

;; Cast vote as assigned mediator
(define-public (cast-mediator-vote
    (dispute-id uint)
    (outcome (string-ascii 20))
    (refund-percentage uint)
    (reasoning (string-ascii 150)))
    (let
        ((dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-NOT-FOUND))
         (mediator-info (unwrap! (map-get? mediators { mediator: tx-sender }) ERR-NOT-MEDIATOR))
         (existing-vote (map-get? mediator-votes { dispute-id: dispute-id, mediator: tx-sender })))
        (asserts! (is-some (index-of (get assigned-mediators dispute) tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
        (asserts! (<= refund-percentage u100) ERR-INVALID-PARAMETERS)
        (asserts! (< stacks-block-height (get resolution-deadline dispute)) ERR-DISPUTE-CLOSED)
        (asserts! (get active mediator-info) ERR-NOT-MEDIATOR)
        (map-set mediator-votes
            { dispute-id: dispute-id, mediator: tx-sender }
            {
                outcome: outcome,
                refund-percentage: refund-percentage,
                reasoning: reasoning,
                voted-at: stacks-block-height
            }
        )
        (try! (update-voting-tally dispute-id outcome refund-percentage))
        (try! (check-and-resolve-dispute dispute-id))
        (ok true)
    )
)

;; Finalize dispute resolution and execute payouts
(define-public (finalize-dispute (dispute-id uint))
    (let
        ((dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-NOT-FOUND))
         (tally (unwrap! (map-get? voting-tallies { dispute-id: dispute-id }) ERR-NOT-FOUND)))
        (asserts! (is-eq (get status dispute) STATUS-RESOLVED) ERR-INVALID-DISPUTE)
        (asserts! (or (is-eq tx-sender (var-get dispute-admin))
                     (is-eq tx-sender (get buyer dispute))
                     (is-eq tx-sender (get seller dispute))) ERR-NOT-AUTHORIZED)
        (try! (execute-dispute-payout dispute-id))
        (try! (reward-mediators dispute-id))
        (try! (update-mediator-stats dispute-id))
        (map-set disputes
            { dispute-id: dispute-id }
            (merge dispute { status: STATUS-CLOSED })
        )
        (ok true)
    )
)

;; Helper functions
(define-private (calculate-dispute-fee (transaction-amount uint))
    (let
        ((percentage-fee (/ (* transaction-amount u5) u100))) ;; 5% of transaction
        (if (> percentage-fee (var-get base-dispute-fee))
            percentage-fee
            (var-get base-dispute-fee)
        )
    )
)

(define-private (validate-mediator-list (mediator-list (list 3 principal)))
    (if (fold check-mediator-active mediator-list true)
        (ok true)
        ERR-NOT-MEDIATOR
    )
)

(define-private (check-mediator-active (mediator principal) (acc bool))
    (and acc 
        (match (map-get? mediators { mediator: mediator })
            mediator-info (get active mediator-info)
            false
        )
    )
)

(define-private (update-voting-tally 
    (dispute-id uint)
    (outcome (string-ascii 20))
    (refund-percentage uint))
    (let
        ((current-tally (unwrap! (map-get? voting-tallies { dispute-id: dispute-id }) ERR-NOT-FOUND))
         (new-total-votes (+ (get total-votes current-tally) u1))
         (new-avg-refund (/ (+ (* (get average-refund-percentage current-tally) (get total-votes current-tally))
                              refund-percentage) 
                           new-total-votes)))
        (map-set voting-tallies
            { dispute-id: dispute-id }
            (merge current-tally {
                buyer-favor-votes: (if (is-eq outcome OUTCOME-BUYER-FAVOR) 
                    (+ (get buyer-favor-votes current-tally) u1)
                    (get buyer-favor-votes current-tally)),
                seller-favor-votes: (if (is-eq outcome OUTCOME-SELLER-FAVOR)
                    (+ (get seller-favor-votes current-tally) u1)
                    (get seller-favor-votes current-tally)),
                partial-refund-votes: (if (is-eq outcome OUTCOME-PARTIAL-REFUND)
                    (+ (get partial-refund-votes current-tally) u1)
                    (get partial-refund-votes current-tally)),
                no-resolution-votes: (if (is-eq outcome OUTCOME-NO-RESOLUTION)
                    (+ (get no-resolution-votes current-tally) u1)
                    (get no-resolution-votes current-tally)),
                total-votes: new-total-votes,
                average-refund-percentage: new-avg-refund
            })
        )
        (ok true)
    )
)

(define-private (check-and-resolve-dispute (dispute-id uint))
    (let
        ((dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-NOT-FOUND))
         (tally (unwrap! (map-get? voting-tallies { dispute-id: dispute-id }) ERR-NOT-FOUND))
         (mediator-count (len (get assigned-mediators dispute)))
         (majority-threshold (+ (/ mediator-count u2) u1)))

        (ok true)
    )
)

(define-private (determine-winning-outcome (tally {buyer-favor-votes: uint, seller-favor-votes: uint, partial-refund-votes: uint, no-resolution-votes: uint, total-votes: uint, average-refund-percentage: uint}))
    (let
        ((buyer-votes (get buyer-favor-votes tally))
         (seller-votes (get seller-favor-votes tally))
         (partial-votes (get partial-refund-votes tally))
         (no-res-votes (get no-resolution-votes tally)))
        (if (and (>= buyer-votes seller-votes) 
                 (>= buyer-votes partial-votes)
                 (>= buyer-votes no-res-votes))
            OUTCOME-BUYER-FAVOR
            (if (and (>= seller-votes partial-votes)
                     (>= seller-votes no-res-votes))
                OUTCOME-SELLER-FAVOR
                (if (>= partial-votes no-res-votes)
                    OUTCOME-PARTIAL-REFUND
                    OUTCOME-NO-RESOLUTION
                )
            )
        )
    )
)

(define-private (calculate-refund-amount 
    (dispute {item-id: uint, buyer: principal, seller: principal, dispute-type: (string-ascii 30), dispute-reason: (string-ascii 200), transaction-amount: uint, dispute-fee: uint, filed-at: uint, status: (string-ascii 20), outcome: (optional (string-ascii 20)), refund-amount: uint, assigned-mediators: (list 3 principal), resolution-deadline: uint})
    (tally {buyer-favor-votes: uint, seller-favor-votes: uint, partial-refund-votes: uint, no-resolution-votes: uint, total-votes: uint, average-refund-percentage: uint})
    (outcome (string-ascii 20)))
    (if (is-eq outcome OUTCOME-BUYER-FAVOR)
        (get transaction-amount dispute)
        (if (is-eq outcome OUTCOME-PARTIAL-REFUND)
            (/ (* (get transaction-amount dispute) (get average-refund-percentage tally)) u100)
            u0
        )
    )
)

(define-private (execute-dispute-payout (dispute-id uint))
    (let
        ((dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-NOT-FOUND)))
        (if (> (get refund-amount dispute) u0)
            (as-contract (stx-transfer? (get refund-amount dispute) tx-sender (get buyer dispute)))
            (ok true)
        )
    )
)

(define-private (reward-mediators (dispute-id uint))
    (let
        ((dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-NOT-FOUND))
         (total-reward (/ (* (get dispute-fee dispute) (var-get mediator-reward-percentage)) u100))
         (mediator-list (get assigned-mediators dispute))
         (reward-per-mediator (/ total-reward (len mediator-list))))
        ;; (fold distribute-mediator-reward mediator-list reward-per-mediator)
        (ok true)
    )
)

(define-private (distribute-mediator-reward (mediator principal) (reward-amount uint))
    (as-contract (stx-transfer? reward-amount tx-sender mediator))
)

(define-private (update-mediator-stats (dispute-id uint))
    (let
        ((dispute (unwrap! (map-get? disputes { dispute-id: dispute-id }) ERR-NOT-FOUND))
         (mediator-list (get assigned-mediators dispute)))
        ;; (fold update-single-mediator-stats mediator-list true)
        (ok true)
    )
)

;; (define-private (update-single-mediator-stats (mediator principal) (acc bool))
;;     (let
;;         ((current-stats (unwrap! (map-get? mediators { mediator: mediator }) ERR-NOT-FOUND)))
;;         (map-set mediators
;;             { mediator: mediator }
;;             (merge current-stats {
;;                 disputes-handled: (+ (get disputes-handled current-stats) u1),
;;                 successful-resolutions: (+ (get successful-resolutions current-stats) u1)
;;             })
;;         )
;;         true
;;     )
;; )

;; Admin functions
(define-public (set-dispute-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dispute-admin)) ERR-NOT-AUTHORIZED)
        (var-set dispute-admin new-admin)
        (ok true)
    )
)

(define-public (update-system-params 
    (new-base-fee uint)
    (new-min-stake uint)
    (new-time-limit uint)
    (new-mediator-reward uint))
    (begin
        (asserts! (is-eq tx-sender (var-get dispute-admin)) ERR-NOT-AUTHORIZED)
        (var-set base-dispute-fee new-base-fee)
        (var-set mediator-min-stake new-min-stake)
        (var-set resolution-time-limit new-time-limit)
        (var-set mediator-reward-percentage new-mediator-reward)
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-dispute (dispute-id uint))
    (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (get-dispute-evidence (dispute-id uint) (evidence-id uint))
    (map-get? dispute-evidence { dispute-id: dispute-id, evidence-id: evidence-id })
)

(define-read-only (get-mediator-info (mediator principal))
    (map-get? mediators { mediator: mediator })
)

(define-read-only (get-mediator-vote (dispute-id uint) (mediator principal))
    (map-get? mediator-votes { dispute-id: dispute-id, mediator: mediator })
)

(define-read-only (get-voting-tally (dispute-id uint))
    (map-get? voting-tallies { dispute-id: dispute-id })
)

(define-read-only (calculate-dispute-fee-preview (transaction-amount uint))
    (calculate-dispute-fee transaction-amount)
)

(define-read-only (is-dispute-expired (dispute-id uint))
    (match (map-get? disputes { dispute-id: dispute-id })
        dispute (>= stacks-block-height (get resolution-deadline dispute))
        true
    )
)

(define-read-only (get-system-params)
    {
        base-dispute-fee: (var-get base-dispute-fee),
        mediator-min-stake: (var-get mediator-min-stake),
        resolution-time-limit: (var-get resolution-time-limit),
        mediator-reward-percentage: (var-get mediator-reward-percentage)
    }
)
