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