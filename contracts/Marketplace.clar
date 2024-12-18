;; Simple Marketplace Contract

;; Constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-WRONG-PRICE (err u401))
(define-constant ERR-NOT-OWNER (err u403))

;; Data Variables
(define-map items 
    { item-id: uint }
    { 
        owner: principal,
        price: uint,
        title: (string-ascii 50),
        is-listed: bool
    }
)

(define-data-var next-item-id uint u1)

;; Public Functions
(define-public (list-item (price uint) (title (string-ascii 50)))
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
                is-listed: true
            }
        )
        (var-set next-item-id (+ item-id u1))
        (ok item-id)
    )
)


(define-public (purchase-item (item-id uint))
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
                is-listed: false
            }
        )
        (ok true)
    )
)


;; Read-only Functions
(define-read-only (get-item (item-id uint))
    (map-get? items {item-id: item-id})
)
