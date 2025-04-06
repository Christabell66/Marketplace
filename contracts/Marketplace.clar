;; Simple Marketplace Contract

;; Constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-WRONG-PRICE (err u401))
(define-constant ERR-NOT-OWNER (err u403))

;; Add category field to items map
(define-map items 
    { item-id: uint }
    { 
        owner: principal,
        price: uint,
        title: (string-ascii 50),
        is-listed: bool,
        category-id: uint
    }
)

(define-data-var next-item-id uint u1)

;; Public Functions
(define-public (list-item (price uint) (category-id uint) (title (string-ascii 50)))
    (let
        (
            (item-id (var-get next-item-id))
        )
        (map-set items
            { item-id: item-id }
            {
                owner: tx-sender,
                price: price,
                title: title,
                is-listed: true,
                category-id: category-id

            }
        )
        (var-set next-item-id (+ item-id u1))
        (ok item-id)
    )
)


(define-public (purchase-item (item-id uint) (category-id uint))
    (let
        (
            (item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND))
            (price (get price item))
            (seller (get owner item))
        )
        (asserts! (get is-listed item) ERR-NOT-FOUND)
        (try! (stx-transfer? price tx-sender seller))
        (map-set items
            { item-id: item-id }
            {
                owner: tx-sender,
                price: price,
                title: (get title item),
                is-listed: false,
                category-id: category-id

            }
        )
        (ok true)
    )
)


;; Read-only Functions
(define-read-only (get-item (item-id uint))
    (map-get? items {item-id: item-id})
)



;; Add to Data Variables
(define-map categories 
    { category-id: uint }
    { category-name: (string-ascii 20) }
)

;; Add this with other data variables
(define-data-var next-category-id uint u1)


;; New function to add categories
(define-public (add-category (category-name (string-ascii 20)))
    (let
        ((category-id (var-get next-category-id)))
        (map-set categories
            { category-id: category-id }
            { category-name: category-name }
        )
        (var-set next-category-id (+ category-id u1))
        (ok category-id)
    )
)


;; Add to Data Variables
(define-map item-discounts
    { item-id: uint }
    { discount-percentage: uint }
)

(define-public (set-discount (item-id uint) (discount uint))
    (let
        ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get owner item)) ERR-NOT-OWNER)
        (asserts! (<= discount u100) (err u401))
        (map-set item-discounts
            { item-id: item-id }
            { discount-percentage: discount }
        )
        (ok true)
    )
)



;; Add to Data Variables
(define-map reservations
    { item-id: uint }
    { 
        reserver: principal,
        expiry: uint
    }
)

(define-public (reserve-item (item-id uint))
    (let
        ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND)))
        (asserts! (get is-listed item) ERR-NOT-FOUND)
        (map-set reservations
            { item-id: item-id }
            { 
                reserver: tx-sender,
                expiry: (+ block-height u144)  ;; 24 hour reservation
            }
        )
        (ok true)
    )
)



;; Add to Data Variables
(define-map seller-ratings
    { seller: principal }
    { 
        total-ratings: uint,
        rating-sum: uint
    }
)

(define-public (rate-seller (seller principal) (rating uint))
    (let
        ((current-rating (default-to { total-ratings: u0, rating-sum: u0 }
            (map-get? seller-ratings {seller: seller}))))
        (asserts! (<= rating u5) (err u401))
        (map-set seller-ratings
            { seller: seller }
            { 
                total-ratings: (+ (get total-ratings current-rating) u1),
                rating-sum: (+ (get rating-sum current-rating) rating)
            }
        )
        (ok true)
    )
)



;; Add to Data Variables
(define-map bids
    { item-id: uint }
    {
        highest-bidder: principal,
        bid-amount: uint
    }
)

(define-public (place-bid (item-id uint) (bid-amount uint))
    (let
        ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND))
         (current-bid (default-to { highest-bidder: tx-sender, bid-amount: u0 }
            (map-get? bids {item-id: item-id}))))
        (asserts! (get is-listed item) ERR-NOT-FOUND)
        (asserts! (> bid-amount (get bid-amount current-bid)) ERR-WRONG-PRICE)
        (map-set bids
            { item-id: item-id }
            {
                highest-bidder: tx-sender,
                bid-amount: bid-amount
            }
        )
        (ok true)
    )
)



;; Add to Data Variables
(define-map item-reviews
    { item-id: uint, reviewer: principal }
    { 
        rating: uint,
        comment: (string-ascii 200),
        timestamp: uint
    }
)

(define-public (add-item-review (item-id uint) (rating uint) (comment (string-ascii 200)))
    (let ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND)))
        (asserts! (<= rating u5) (err u401))
        (map-set item-reviews
            { item-id: item-id, reviewer: tx-sender }
            { 
                rating: rating,
                comment: comment,
                timestamp: block-height
            }
        )
        (ok true)
    )
)



(define-map wishlists
    { user: principal, item-id: uint }
    { added-at: uint }
)

(define-public (add-to-wishlist (item-id uint))
    (let ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND)))
        (map-set wishlists
            { user: tx-sender, item-id: item-id }
            { added-at: block-height }
        )
        (ok true)
    )
)



(define-map flash-sales
    { item-id: uint }
    {
        discounted-price: uint,
        end-block: uint
    }
)

(define-public (create-flash-sale (item-id uint) (discounted-price uint) (duration uint))
    (let ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get owner item)) ERR-NOT-OWNER)
        (map-set flash-sales
            { item-id: item-id }
            {
                discounted-price: discounted-price,
                end-block: (+ block-height duration)
            }
        )
        (ok true)
    )
)




(define-map referrals
    { referrer: principal }
    { 
        total-sales: uint,
        commission-earned: uint
    }
)

(define-constant REFERRAL-PERCENTAGE u5)

(define-public (purchase-with-referral (item-id uint) (referrer principal))
    (let
        (
            (item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND))
            (price (get price item))
            (commission (/ (* price REFERRAL-PERCENTAGE) u100))
        )
        (try! (stx-transfer? commission tx-sender referrer))
        (try! (purchase-item item-id u1))
        (ok true)
    )
)



(define-map trade-ins
    { item-id: uint }
    {
        trade-value: uint,
        accepted-categories: (list 5 uint)
    }
)

(define-public (offer-trade-in (old-item-id uint) (new-item-id uint))
    (let
        (
            (old-item (unwrap! (map-get? items {item-id: old-item-id}) ERR-NOT-FOUND))
            (new-item (unwrap! (map-get? items {item-id: new-item-id}) ERR-NOT-FOUND))
            (trade-in-details (unwrap! (map-get? trade-ins {item-id: new-item-id}) ERR-NOT-FOUND))
        )
        (asserts! (is-eq (get owner old-item) tx-sender) ERR-NOT-OWNER)
        (ok true)
    )
)



(define-map gift-cards
    { card-id: uint }
    {
        value: uint,
        creator: principal,
        recipient: principal,
        is-used: bool
    }
)

(define-data-var next-card-id uint u1)

(define-public (create-gift-card (value uint) (recipient principal))
    (let ((card-id (var-get next-card-id)))
        (try! (stx-transfer? value tx-sender (as-contract tx-sender)))
        (map-set gift-cards
            { card-id: card-id }
            {
                value: value,
                creator: tx-sender,
                recipient: recipient,
                is-used: false
            }
        )
        (var-set next-card-id (+ card-id u1))
        (ok card-id)
    )
)


(define-map loyalty-points
    { user: principal }
    { points: uint }
)

(define-constant POINTS-PER-PURCHASE u10)

(define-public (redeem-points (points-to-redeem uint))
    (let
        (
            (user-points (default-to { points: u0 } (map-get? loyalty-points {user: tx-sender})))
            (current-points (get points user-points))
        )
        (asserts! (>= current-points points-to-redeem) (err u401))
        (map-set loyalty-points
            { user: tx-sender }
            { points: (- current-points points-to-redeem) }
        )
        (try! (stx-transfer? (* points-to-redeem u1000) (as-contract tx-sender) tx-sender))
        (ok true)
    )
)


;; Bundle Deals - Allow sellers to create discounted item bundles
(define-map bundles 
    { bundle-id: uint }
    {
        items: (list 5 uint),
        bundle-price: uint,
        creator: principal,
        is-active: bool
    }
)

(define-data-var next-bundle-id uint u1)

(define-public (create-bundle (item-ids (list 5 uint)) (bundle-price uint))
    (let ((bundle-id (var-get next-bundle-id)))
        ;; Verify ownership of all items
        (map-set bundles
            { bundle-id: bundle-id }
            {
                items: item-ids,
                bundle-price: bundle-price,
                creator: tx-sender,
                is-active: true
            }
        )
        (var-set next-bundle-id (+ bundle-id u1))
        (ok bundle-id)
    )
)

(define-map timed-listings
    { item-id: uint }
    {
        end-height: uint,
        min-price: uint
    }
)

(define-public (create-timed-listing (item-id uint) (duration uint) (min-price uint))
    (let ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get owner item)) ERR-NOT-OWNER)
        (map-set timed-listings
            { item-id: item-id }
            {
                end-height: (+ block-height duration),
                min-price: min-price
            }
        )
        (ok true)
    )
)


(define-map featured-items
    { item-id: uint }
    {
        featured-until: uint,
        spotlight-position: uint
    }
)

(define-public (feature-item (item-id uint) (duration uint) (position uint))
    (let ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get owner item)) ERR-NOT-OWNER)
        (map-set featured-items
            { item-id: item-id }
            {
                featured-until: (+ block-height duration),
                spotlight-position: position
            }
        )
        (ok true)
    )
)


(define-map trade-requests
    { request-id: uint }
    {
        offered-item: uint,
        requested-item: uint,
        requester: principal,
        status: (string-ascii 10)
    }
)

(define-data-var next-request-id uint u1)

(define-public (create-trade-request (offered-item uint) (requested-item uint))
    (let ((request-id (var-get next-request-id)))
        (map-set trade-requests
            { request-id: request-id }
            {
                offered-item: offered-item,
                requested-item: requested-item,
                requester: tx-sender,
                status: "pending"
            }
        )
        (var-set next-request-id (+ request-id u1))
        (ok request-id)
    )
)
(define-map subscriptions
    { subscription-id: uint }
    {
        item-id: uint,
        subscriber: principal,
        renewal-height: uint,
        auto-renew: bool
    }
)

(define-data-var next-subscription-id uint u1)

(define-public (create-subscription (item-id uint) (duration uint))
    (let ((subscription-id (var-get next-subscription-id)))
        (map-set subscriptions
            { subscription-id: subscription-id }
            {
                item-id: item-id,
                subscriber: tx-sender,
                renewal-height: (+ block-height duration),
                auto-renew: true
            }
        )
        (var-set next-subscription-id (+ subscription-id u1))
        (ok subscription-id)
    )
)


(define-map bulk-discounts
    { item-id: uint }
    {
        min-quantity: uint,
        discount-percentage: uint
    }
)

(define-public (set-bulk-discount (item-id uint) (min-quantity uint) (discount uint))
    (let ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND)))
        (asserts! (is-eq tx-sender (get owner item)) ERR-NOT-OWNER)
        (asserts! (<= discount u100) (err u401))
        (map-set bulk-discounts
            { item-id: item-id }
            {
                min-quantity: min-quantity,
                discount-percentage: discount
            }
        )
        (ok true)
    )
)


(define-map escrow-transactions
    { escrow-id: uint }
    {
        buyer: principal,
        seller: principal,
        item-id: uint,
        amount: uint,
        status: (string-ascii 20),
        created-at: uint
    }
)

(define-data-var next-escrow-id uint u1)

(define-public (create-escrow (item-id uint))
    (let
        ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND))
         (escrow-id (var-get next-escrow-id))
         (price (get price item))
         (seller (get owner item)))
        (asserts! (get is-listed item) ERR-NOT-FOUND)
        (try! (stx-transfer? price tx-sender (as-contract tx-sender)))
        (map-set escrow-transactions
            { escrow-id: escrow-id }
            {
                buyer: tx-sender,
                seller: seller,
                item-id: item-id,
                amount: price,
                status: "pending",
                created-at: block-height
            }
        )
        (var-set next-escrow-id (+ escrow-id u1))
        (ok escrow-id)
    )
)

(define-public (release-escrow (escrow-id uint))
    (let
        ((escrow (unwrap! (map-get? escrow-transactions {escrow-id: escrow-id}) ERR-NOT-FOUND))
         (item-id (get item-id escrow))
         (item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND))
         (amount (get amount escrow))
         (seller (get seller escrow))
         (buyer (get buyer escrow)))
        (asserts! (is-eq tx-sender buyer) ERR-NOT-OWNER)
        (asserts! (is-eq (get status escrow) "pending") ERR-NOT-FOUND)
        (try! (as-contract (stx-transfer? amount tx-sender seller)))
        (map-set escrow-transactions
            { escrow-id: escrow-id }
            (merge escrow { status: "completed" })
        )
        (map-set items
            { item-id: item-id }
            {
                owner: buyer,
                price: (get price item),
                title: (get title item),
                is-listed: false,
                category-id: (get category-id item)
            }
        )
        (ok true)
    )
)

(define-public (cancel-escrow (escrow-id uint))
    (let
        ((escrow (unwrap! (map-get? escrow-transactions {escrow-id: escrow-id}) ERR-NOT-FOUND))
         (amount (get amount escrow))
         (buyer (get buyer escrow)))
        (asserts! (or (is-eq tx-sender buyer) (is-eq tx-sender (get seller escrow))) ERR-NOT-OWNER)
        (asserts! (is-eq (get status escrow) "pending") ERR-NOT-FOUND)
        (try! (as-contract (stx-transfer? amount tx-sender buyer)))
        (map-set escrow-transactions
            { escrow-id: escrow-id }
            (merge escrow { status: "cancelled" })
        )
        (ok true)
    )
)



(define-map verified-sellers
    { seller: principal }
    { 
        is-verified: bool,
        verification-date: uint,
        verifier: principal
    }
)

(define-data-var marketplace-admin principal tx-sender)

(define-public (set-marketplace-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get marketplace-admin)) ERR-NOT-OWNER)
        (var-set marketplace-admin new-admin)
        (ok true)
    )
)

(define-public (verify-seller (seller principal))
    (begin
        (asserts! (is-eq tx-sender (var-get marketplace-admin)) ERR-NOT-OWNER)
        (map-set verified-sellers
            { seller: seller }
            { 
                is-verified: true,
                verification-date: block-height,
                verifier: tx-sender
            }
        )
        (ok true)
    )
)

(define-read-only (is-verified-seller (seller principal))
    (default-to false (get is-verified (map-get? verified-sellers { seller: seller })))
)



(define-map auctions
    { auction-id: uint }
    {
        item-id: uint,
        seller: principal,
        start-price: uint,
        reserve-price: uint,
        end-height: uint,
        highest-bidder: (optional principal),
        highest-bid: uint,
        status: (string-ascii 20)
    }
)

(define-data-var next-auction-id uint u1)

(define-public (create-auction (item-id uint) (start-price uint) (reserve-price uint) (duration uint))
    (let
        ((item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND))
         (auction-id (var-get next-auction-id)))
        (asserts! (is-eq tx-sender (get owner item)) ERR-NOT-OWNER)
        (map-set auctions
            { auction-id: auction-id }
            {
                item-id: item-id,
                seller: tx-sender,
                start-price: start-price,
                reserve-price: reserve-price,
                end-height: (+ block-height duration),
                highest-bidder: none,
                highest-bid: u0,
                status: "active"
            }
        )
        (map-set items
            { item-id: item-id }
            (merge item { is-listed: false })
        )
        (var-set next-auction-id (+ auction-id u1))
        (ok auction-id)
    )
)

(define-public (place-auction-bid (auction-id uint) (bid-amount uint))
    (let
        ((auction (unwrap! (map-get? auctions {auction-id: auction-id}) ERR-NOT-FOUND))
         (current-bid (get highest-bid auction))
         (current-bidder (get highest-bidder auction)))
        (asserts! (is-eq (get status auction) "active") ERR-NOT-FOUND)
        (asserts! (< block-height (get end-height auction)) ERR-NOT-FOUND)
        (asserts! (> bid-amount current-bid) ERR-WRONG-PRICE)
        (asserts! (>= bid-amount (get start-price auction)) ERR-WRONG-PRICE)
        
        (match current-bidder
            prev-bidder (try! (stx-transfer? current-bid (as-contract tx-sender) prev-bidder))
            true
        )
        
        (try! (stx-transfer? bid-amount tx-sender (as-contract tx-sender)))
        
        (map-set auctions
            { auction-id: auction-id }
            (merge auction {
                highest-bidder: (some tx-sender),
                highest-bid: bid-amount
            })
        )
        (ok true)
    )
)

(define-public (finalize-auction (auction-id uint))
    (let
        ((auction (unwrap! (map-get? auctions {auction-id: auction-id}) ERR-NOT-FOUND))
         (item-id (get item-id auction))
         (item (unwrap! (map-get? items {item-id: item-id}) ERR-NOT-FOUND))
         (highest-bid (get highest-bid auction))
         (highest-bidder (get highest-bidder auction))
         (seller (get seller auction))
         (reserve-price (get reserve-price auction)))
        (asserts! (is-eq (get status auction) "active") ERR-NOT-FOUND)
        (asserts! (>= block-height (get end-height auction)) ERR-NOT-FOUND)
        
        (match highest-bidder
            winner 
            (begin
                (asserts! (>= highest-bid reserve-price) ERR-WRONG-PRICE)
                (try! (as-contract (stx-transfer? highest-bid tx-sender seller)))
                (map-set items
                    { item-id: item-id }
                    (merge item {
                        owner: winner,
                        is-listed: false
                    })
                )
                (map-set auctions
                    { auction-id: auction-id }
                    (merge auction { status: "completed" })
                )
                (ok true)
            )
            (begin
                (map-set auctions
                    { auction-id: auction-id }
                    (merge auction { status: "ended-no-sale" })
                )
                (map-set items
                    { item-id: item-id }
                    (merge item { is-listed: true })
                )
                (ok true)
            )
        )
    )
)

(define-map marketplace-stats
    { stat-id: (string-ascii 20) }
    { value: uint }
)

(define-map seller-stats
    { seller: principal }
    {
        items-sold: uint,
        items-listed: uint,
        total-sales-volume: uint,
        last-sale-height: uint
    }
)

(define-public (increment-marketplace-stat (stat-id (string-ascii 20)) (increment uint))
    (let
        ((current-stat (default-to { value: u0 } (map-get? marketplace-stats { stat-id: stat-id }))))
        (map-set marketplace-stats
            { stat-id: stat-id }
            { value: (+ (get value current-stat) increment) }
        )
        (ok true)
    )
)

(define-public (update-seller-stats (seller principal) (sale-amount uint))
    (let
        ((current-stats (default-to 
                        { items-sold: u0, items-listed: u0, total-sales-volume: u0, last-sale-height: u0 } 
                        (map-get? seller-stats { seller: seller }))))
        (map-set seller-stats
            { seller: seller }
            {
                items-sold: (+ (get items-sold current-stats) u1),
                items-listed: (get items-listed current-stats),
                total-sales-volume: (+ (get total-sales-volume current-stats) sale-amount),
                last-sale-height: block-height
            }
        )
        (ok true)
    )
)

(define-read-only (get-marketplace-stat (stat-id (string-ascii 20)))
    (default-to { value: u0 } (map-get? marketplace-stats { stat-id: stat-id }))
)

(define-read-only (get-seller-stats (seller principal))
    (default-to 
        { items-sold: u0, items-listed: u0, total-sales-volume: u0, last-sale-height: u0 } 
        (map-get? seller-stats { seller: seller }))
)





