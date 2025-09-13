(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-NOT-OWNER (err u403))
(define-constant ERR-RENTAL-ACTIVE (err u420))
(define-constant ERR-RENTAL-EXPIRED (err u421))
(define-constant ERR-INSUFFICIENT-DEPOSIT (err u422))

(define-map rental-listings
    { item-id: uint }
    {
        owner: principal,
        rental-price-per-block: uint,
        max-rental-duration: uint,
        security-deposit: uint,
        is-available: bool
    }
)

(define-map active-rentals
    { rental-id: uint }
    {
        item-id: uint,
        renter: principal,
        owner: principal,
        rental-start: uint,
        rental-end: uint,
        total-cost: uint,
        deposit-paid: uint,
        status: (string-ascii 10)
    }
)

(define-data-var next-rental-id uint u1)

(define-public (list-for-rent 
    (item-id uint) 
    (price-per-block uint) 
    (max-duration uint) 
    (deposit uint))
    (begin
        (map-set rental-listings
            { item-id: item-id }
            {
                owner: tx-sender,
                rental-price-per-block: price-per-block,
                max-rental-duration: max-duration,
                security-deposit: deposit,
                is-available: true
            }
        )
        (ok true)
    )
)

(define-public (rent-item (item-id uint) (duration uint))
    (let
        ((listing (unwrap! (map-get? rental-listings { item-id: item-id }) ERR-NOT-FOUND))
         (rental-id (var-get next-rental-id))
         (total-cost (* (get rental-price-per-block listing) duration))
         (deposit (get security-deposit listing))
         (total-payment (+ total-cost deposit)))
        (asserts! (get is-available listing) ERR-NOT-FOUND)
        (asserts! (<= duration (get max-rental-duration listing)) ERR-RENTAL-EXPIRED)
        (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
        (map-set active-rentals
            { rental-id: rental-id }
            {
                item-id: item-id,
                renter: tx-sender,
                owner: (get owner listing),
                rental-start: stacks-block-height,
                rental-end: (+ stacks-block-height duration),
                total-cost: total-cost,
                deposit-paid: deposit,
                status: "active"
            }
        )
        (map-set rental-listings
            { item-id: item-id }
            (merge listing { is-available: false })
        )
        (var-set next-rental-id (+ rental-id u1))
        (ok rental-id)
    )
)

(define-public (return-rental (rental-id uint))
    (let
        ((rental (unwrap! (map-get? active-rentals { rental-id: rental-id }) ERR-NOT-FOUND))
         (item-id (get item-id rental))
         (listing (unwrap! (map-get? rental-listings { item-id: item-id }) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get renter rental)) ERR-NOT-OWNER)
        (asserts! (is-eq (get status rental) "active") ERR-NOT-FOUND)
        (try! (as-contract (stx-transfer? (get total-cost rental) tx-sender (get owner rental))))
        (try! (as-contract (stx-transfer? (get deposit-paid rental) tx-sender (get renter rental))))
        (map-set active-rentals
            { rental-id: rental-id }
            (merge rental { status: "returned" })
        )
        (map-set rental-listings
            { item-id: item-id }
            (merge listing { is-available: true })
        )
        (ok true)
    )
)

(define-public (claim-expired-rental (rental-id uint))
    (let
        ((rental (unwrap! (map-get? active-rentals { rental-id: rental-id }) ERR-NOT-FOUND))
         (item-id (get item-id rental))
         (listing (unwrap! (map-get? rental-listings { item-id: item-id }) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get owner rental)) ERR-NOT-OWNER)
        (asserts! (>= stacks-block-height (get rental-end rental)) ERR-RENTAL-ACTIVE)
        (asserts! (is-eq (get status rental) "active") ERR-NOT-FOUND)
        (try! (as-contract (stx-transfer? (get total-cost rental) tx-sender (get owner rental))))
        (map-set active-rentals
            { rental-id: rental-id }
            (merge rental { status: "expired" })
        )
        (map-set rental-listings
            { item-id: item-id }
            (merge listing { is-available: true })
        )
        (ok true)
    )
)

(define-public (update-rental-terms 
    (item-id uint) 
    (new-price uint) 
    (new-duration uint) 
    (new-deposit uint))
    (let
        ((listing (unwrap! (map-get? rental-listings { item-id: item-id }) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get owner listing)) ERR-NOT-OWNER)
        (asserts! (get is-available listing) ERR-RENTAL-ACTIVE)
        (map-set rental-listings
            { item-id: item-id }
            (merge listing {
                rental-price-per-block: new-price,
                max-rental-duration: new-duration,
                security-deposit: new-deposit
            })
        )
        (ok true)
    )
)

(define-public (remove-rental-listing (item-id uint))
    (let
        ((listing (unwrap! (map-get? rental-listings { item-id: item-id }) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get owner listing)) ERR-NOT-OWNER)
        (asserts! (get is-available listing) ERR-RENTAL-ACTIVE)
        (map-delete rental-listings { item-id: item-id })
        (ok true)
    )
)

(define-read-only (get-rental-listing (item-id uint))
    (map-get? rental-listings { item-id: item-id })
)

(define-read-only (get-active-rental (rental-id uint))
    (map-get? active-rentals { rental-id: rental-id })
)

(define-read-only (get-rental-status (rental-id uint))
    (match (map-get? active-rentals { rental-id: rental-id })
        rental (get status rental)
        "not-found"
    )
)

(define-read-only (is-rental-expired (rental-id uint))
    (match (map-get? active-rentals { rental-id: rental-id })
        rental (>= stacks-block-height (get rental-end rental))
        true
    )
)

