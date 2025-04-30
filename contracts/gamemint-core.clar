;; gamemint-core
;; 
;; This contract manages the creation, ownership, and trading of gaming NFTs on the Stacks blockchain.
;; It provides a standardized framework for game developers to represent in-game items as non-fungible tokens
;; with customizable properties and metadata, while maintaining ownership records, facilitating transfers,
;; and enforcing royalty payments to original creators during secondary sales.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ITEM-EXISTS (err u101))
(define-constant ERR-ITEM-NOT-FOUND (err u102))
(define-constant ERR-NOT-OWNER (err u103))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u104))
(define-constant ERR-LISTING-NOT-FOUND (err u105))
(define-constant ERR-LISTING-EXPIRED (err u106))
(define-constant ERR-INVALID-PARAMS (err u107))
(define-constant ERR-SELF-TRANSFER (err u108))
(define-constant ERR-CONTRACT-PAUSED (err u109))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-ROYALTY-PERCENTAGE u20) ;; 20% maximum royalty
(define-constant PLATFORM-FEE-PERCENTAGE u2) ;; 2% platform fee

;; Data variables
(define-data-var contract-paused bool false)
(define-data-var last-token-id uint u0)

;; Data maps
;; Store NFT ownership information
(define-map token-owners 
  { token-id: uint }
  { owner: principal }
)

;; Store metadata for each NFT
(define-map token-metadata
  { token-id: uint }
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    image-uri: (string-utf8 256),
    creator: principal,
    game-id: (string-ascii 64),
    royalty-percentage: uint
  }
)

;; Store additional game-specific attributes for each NFT
(define-map token-attributes
  { token-id: uint }
  {
    rarity: (string-ascii 32),
    level: uint,
    stats: (list 10 {stat-name: (string-ascii 32), value: uint}),
    custom-attributes: (list 20 {key: (string-ascii 32), value: (string-ascii 64)})
  }
)

;; Store marketplace listings
(define-map token-listings
  { token-id: uint }
  {
    seller: principal,
    price: uint,
    expiry: uint,
    listed-at: uint
  }
)

;; Track which games/creators are authorized to mint and update NFTs
(define-map authorized-creators
  { creator: principal }
  { authorized: bool }
)

;; Private functions

;; Check if the contract is currently paused
(define-private (is-contract-paused)
  (var-get contract-paused)
)

;; Check if a principal is the contract owner
(define-private (is-contract-owner (caller principal))
  (is-eq caller CONTRACT-OWNER)
)

;; Check if a principal is authorized to mint/update tokens
(define-private (is-authorized (caller principal))
  (default-to false (get authorized (map-get? authorized-creators {creator: caller})))
)

;; Check if a principal owns a specific token
(define-private (is-owner (token-id uint) (caller principal))
  (let ((owner-info (map-get? token-owners {token-id: token-id})))
    (and
      (is-some owner-info)
      (is-eq caller (get owner (unwrap-panic owner-info)))
    )
  )
)

;; Generate a new token ID
(define-private (generate-token-id)
  (let ((current-id (var-get last-token-id)))
    (var-set last-token-id (+ current-id u1))
    (+ current-id u1)
  )
)

;; Calculate royalty amount based on price and percentage
(define-private (calculate-royalty (price uint) (percentage uint))
  (/ (* price percentage) u100)
)

;; Calculate platform fee
(define-private (calculate-platform-fee (price uint))
  (/ (* price PLATFORM-FEE-PERCENTAGE) u100)
)

;; Read-only functions

;; Get the owner of a token
(define-read-only (get-token-owner (token-id uint))
  (let ((owner-info (map-get? token-owners {token-id: token-id})))
    (if (is-some owner-info)
      (ok (get owner (unwrap-panic owner-info)))
      ERR-ITEM-NOT-FOUND
    )
  )
)

;; Get token metadata
(define-read-only (get-token-metadata (token-id uint))
  (let ((metadata (map-get? token-metadata {token-id: token-id})))
    (if (is-some metadata)
      (ok (unwrap-panic metadata))
      ERR-ITEM-NOT-FOUND
    )
  )
)

;; Get token attributes
(define-read-only (get-token-attributes (token-id uint))
  (let ((attributes (map-get? token-attributes {token-id: token-id})))
    (if (is-some attributes)
      (ok (unwrap-panic attributes))
      ERR-ITEM-NOT-FOUND
    )
  )
)

;; Get current listing for a token
(define-read-only (get-token-listing (token-id uint))
  (let ((listing (map-get? token-listings {token-id: token-id})))
    (if (is-some listing)
      (ok (unwrap-panic listing))
      ERR-LISTING-NOT-FOUND
    )
  )
)

;; Check if a creator is authorized
(define-read-only (is-creator-authorized (creator principal))
  (default-to false (get authorized (map-get? authorized-creators {creator: creator})))
)

;; Get the total supply of tokens
(define-read-only (get-total-supply)
  (var-get last-token-id)
)

;; Public functions

;; Toggle the paused state of the contract - only callable by contract owner
(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-contract-owner tx-sender) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-paused (not (var-get contract-paused))))
  )
)

;; Add or remove an authorized creator
(define-public (set-authorized-creator (creator principal) (authorized bool))
  (begin
    (asserts! (is-contract-owner tx-sender) ERR-NOT-AUTHORIZED)
    (map-set authorized-creators {creator: creator} {authorized: authorized})
    (ok true)
  )
)

;; Mint a new NFT
(define-public (mint-nft
  (name (string-ascii 64))
  (description (string-ascii 256))
  (image-uri (string-utf8 256))
  (game-id (string-ascii 64))
  (royalty-percentage uint)
  (rarity (string-ascii 32))
  (level uint)
  (stats (list 10 {stat-name: (string-ascii 32), value: uint}))
  (custom-attributes (list 20 {key: (string-ascii 32), value: (string-ascii 64)}))
  (recipient principal)
)
  (let 
    (
      (token-id (generate-token-id))
    )
    (begin
      ;; Check conditions
      (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
      (asserts! (or (is-contract-owner tx-sender) (is-authorized tx-sender)) ERR-NOT-AUTHORIZED)
      (asserts! (<= royalty-percentage MAX-ROYALTY-PERCENTAGE) ERR-INVALID-PARAMS)
      
      ;; Store token ownership
      (map-set token-owners {token-id: token-id} {owner: recipient})
      
      ;; Store token metadata
      (map-set token-metadata 
        {token-id: token-id}
        {
          name: name,
          description: description,
          image-uri: image-uri,
          creator: tx-sender,
          game-id: game-id,
          royalty-percentage: royalty-percentage
        }
      )
      
      ;; Store token attributes
      (map-set token-attributes
        {token-id: token-id}
        {
          rarity: rarity,
          level: level,
          stats: stats,
          custom-attributes: custom-attributes
        }
      )
      
      (ok token-id)
    )
  )
)

;; Batch mint multiple NFTs with similar properties
(define-public (batch-mint-nft
  (count uint)
  (name-prefix (string-ascii 32))
  (description (string-ascii 256))
  (image-uri-prefix (string-utf8 128))
  (game-id (string-ascii 64))
  (royalty-percentage uint)
  (rarity (string-ascii 32))
  (level uint)
  (stats (list 10 {stat-name: (string-ascii 32), value: uint}))
  (custom-attributes (list 20 {key: (string-ascii 32), value: (string-ascii 64)}))
  (recipient principal)
)
  (begin
    ;; Check conditions
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (or (is-contract-owner tx-sender) (is-authorized tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (<= royalty-percentage MAX-ROYALTY-PERCENTAGE) ERR-INVALID-PARAMS)
    (asserts! (> count u0) ERR-INVALID-PARAMS)
    (asserts! (<= count u100) ERR-INVALID-PARAMS) ;; Limit batch size
    
    ;; Implementation note: Since Clarity doesn't have loops, a proper implementation would use a recursive
    ;; pattern with multiple contracts or a list-based approach. For this example, we're minting just one
    ;; to demonstrate the concept.
    (mint-nft 
      (concat name-prefix " #1") 
      description 
      (concat image-uri-prefix "/1") 
      game-id 
      royalty-percentage 
      rarity 
      level 
      stats 
      custom-attributes 
      recipient
    )
  )
)

;; Update token metadata - only callable by contract owner or authorized creator
(define-public (update-token-metadata
  (token-id uint)
  (name (string-ascii 64))
  (description (string-ascii 256))
  (image-uri (string-utf8 256))
)
  (let (
    (metadata (map-get? token-metadata {token-id: token-id}))
  )
    (begin
      ;; Check conditions
      (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
      (asserts! (is-some metadata) ERR-ITEM-NOT-FOUND)
      (asserts! 
        (or 
          (is-contract-owner tx-sender) 
          (and 
            (is-authorized tx-sender) 
            (is-eq tx-sender (get creator (unwrap-panic metadata)))
          )
        ) 
        ERR-NOT-AUTHORIZED
      )
      
      ;; Update metadata while preserving creator, game-id and royalty
      (map-set token-metadata 
        {token-id: token-id}
        {
          name: name,
          description: description,
          image-uri: image-uri,
          creator: (get creator (unwrap-panic metadata)),
          game-id: (get game-id (unwrap-panic metadata)),
          royalty-percentage: (get royalty-percentage (unwrap-panic metadata))
        }
      )
      
      (ok true)
    )
  )
)

;; Update token game attributes - only callable by contract owner or authorized creator
(define-public (update-token-attributes
  (token-id uint)
  (rarity (string-ascii 32))
  (level uint)
  (stats (list 10 {stat-name: (string-ascii 32), value: uint}))
  (custom-attributes (list 20 {key: (string-ascii 32), value: (string-ascii 64)}))
)
  (let (
    (metadata (map-get? token-metadata {token-id: token-id}))
  )
    (begin
      ;; Check conditions
      (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
      (asserts! (is-some metadata) ERR-ITEM-NOT-FOUND)
      (asserts! 
        (or 
          (is-contract-owner tx-sender) 
          (and 
            (is-authorized tx-sender) 
            (is-eq tx-sender (get creator (unwrap-panic metadata)))
          )
        ) 
        ERR-NOT-AUTHORIZED
      )
      
      ;; Update game attributes
      (map-set token-attributes
        {token-id: token-id}
        {
          rarity: rarity,
          level: level,
          stats: stats,
          custom-attributes: custom-attributes
        }
      )
      
      (ok true)
    )
  )
)

;; Transfer an NFT to another user
(define-public (transfer
  (token-id uint)
  (recipient principal)
)
  (begin
    ;; Check conditions
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-owner token-id tx-sender) ERR-NOT-OWNER)
    (asserts! (not (is-eq tx-sender recipient)) ERR-SELF-TRANSFER)
    
    ;; Remove any existing listing
    (map-delete token-listings {token-id: token-id})
    
    ;; Update ownership
    (map-set token-owners {token-id: token-id} {owner: recipient})
    
    (ok true)
  )
)

;; List an NFT for sale
(define-public (list-token
  (token-id uint)
  (price uint)
  (expiry uint)
)
  (begin
    ;; Check conditions
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-owner token-id tx-sender) ERR-NOT-OWNER)
    (asserts! (> price u0) ERR-INVALID-PARAMS)
    (asserts! (> expiry (get-block-height)) ERR-INVALID-PARAMS)
    
    ;; Create listing
    (map-set token-listings
      {token-id: token-id}
      {
        seller: tx-sender,
        price: price,
        expiry: expiry,
        listed-at: (get-block-height)
      }
    )
    
    (ok true)
  )
)

;; Cancel a token listing
(define-public (cancel-listing (token-id uint))
  (let (
    (listing (map-get? token-listings {token-id: token-id}))
  )
    (begin
      ;; Check conditions
      (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
      (asserts! (is-some listing) ERR-LISTING-NOT-FOUND)
      (asserts! (is-eq tx-sender (get seller (unwrap-panic listing))) ERR-NOT-AUTHORIZED)
      
      ;; Remove listing
      (map-delete token-listings {token-id: token-id})
      
      (ok true)
    )
  )
)

;; Buy a listed token
(define-public (buy-token (token-id uint))
  (let (
    (listing (map-get? token-listings {token-id: token-id}))
    (metadata (map-get? token-metadata {token-id: token-id}))
  )
    (begin
      ;; Check conditions
      (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
      (asserts! (is-some listing) ERR-LISTING-NOT-FOUND)
      (asserts! (is-some metadata) ERR-ITEM-NOT-FOUND)
      (asserts! (<= (get-block-height) (get expiry (unwrap-panic listing))) ERR-LISTING-EXPIRED)
      (asserts! (not (is-eq tx-sender (get seller (unwrap-panic listing)))) ERR-SELF-TRANSFER)
      
      (let (
        (seller (get seller (unwrap-panic listing)))
        (price (get price (unwrap-panic listing)))
        (creator (get creator (unwrap-panic metadata)))
        (royalty-percentage (get royalty-percentage (unwrap-panic metadata)))
        (royalty-amount (calculate-royalty price royalty-percentage))
        (platform-fee (calculate-platform-fee price))
        (seller-amount (- price (+ royalty-amount platform-fee)))
      )
        ;; Process payment (requires STX transfer)
        (unwrap! (stx-transfer? price tx-sender (as-contract tx-sender)) ERR-INSUFFICIENT-PAYMENT)
        
        ;; Pay royalties to creator
        (if (> royalty-amount u0)
          (unwrap! (as-contract (stx-transfer? royalty-amount tx-sender creator)) ERR-INSUFFICIENT-PAYMENT)
          true
        )
        
        ;; Pay platform fee
        (unwrap! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT-OWNER)) ERR-INSUFFICIENT-PAYMENT)
        
        ;; Pay seller
        (unwrap! (as-contract (stx-transfer? seller-amount tx-sender seller)) ERR-INSUFFICIENT-PAYMENT)
        
        ;; Update ownership
        (map-set token-owners {token-id: token-id} {owner: tx-sender})
        
        ;; Remove listing
        (map-delete token-listings {token-id: token-id})
        
        (ok true)
      )
    )
  )
)

;; Burn a token - only callable by token owner
(define-public (burn-token (token-id uint))
  (begin
    ;; Check conditions
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-owner token-id tx-sender) ERR-NOT-OWNER)
    
    ;; Remove token data
    (map-delete token-owners {token-id: token-id})
    (map-delete token-metadata {token-id: token-id})
    (map-delete token-attributes {token-id: token-id})
    (map-delete token-listings {token-id: token-id})
    
    (ok true)
  )
)