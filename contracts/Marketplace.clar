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
