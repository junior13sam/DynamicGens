;; Dynamic Generative NFT Minting Contract
;; This contract enables minting of unique NFTs with algorithmically generated traits
;; based on block data, user inputs, and pseudo-random generation techniques.
;; Each NFT contains dynamically generated attributes that make it truly unique.
;; Features include trait evolution, breeding mechanics, and advanced rarity systems.

;; Constants for contract configuration and limits
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-mint-limit-exceeded (err u103))
(define-constant err-contract-paused (err u104))
(define-constant err-invalid-trait (err u105))
(define-constant err-evolution-cooldown (err u106))
(define-constant err-breeding-failed (err u107))
(define-constant err-invalid-generation (err u108))

;; NFT collection configuration constants
(define-constant collection-limit u10000)
(define-constant mint-price u1000000) ;; 1 STX in microSTX
(define-constant evolution-price u500000) ;; 0.5 STX for evolution
(define-constant breeding-price u2000000) ;; 2 STX for breeding
(define-constant max-traits-per-category u10)
(define-constant evolution-cooldown-blocks u144) ;; ~24 hours
(define-constant max-generation u5)

;; Data maps and variables for NFT state management
(define-map nft-traits uint 
  {
    background: uint,
    body: uint, 
    eyes: uint,
    mouth: uint,
    accessory: uint,
    rarity-score: uint,
    generation-seed: uint,
    generation: uint,
    birth-block: uint,
    evolution-count: uint,
    parent-one: (optional uint),
    parent-two: (optional uint)
  }
)

(define-map token-uris uint (optional (string-ascii 256)))
(define-map token-owners uint principal)
(define-map owned-tokens principal (list 50 uint))
(define-map evolution-history uint (list 10 uint))
(define-map last-evolution-block uint uint)
(define-map breeding-pairs {parent-one: uint, parent-two: uint} uint)

;; Contract state variables
(define-data-var next-token-id uint u1)
(define-data-var contract-paused bool false)
(define-data-var total-minted uint u0)
(define-data-var total-evolved uint u0)
(define-data-var total-bred uint u0)
;; FIXED: Reduced base-uri length to accommodate token IDs
(define-data-var base-uri (string-ascii 200) "https://api.dynft.com/metadata/")
(define-data-var evolution-enabled bool true)
(define-data-var breeding-enabled bool true)

;; Private helper functions for trait generation and validation

;; Helper function to find maximum of two uints
(define-private (max-uint (a uint) (b uint))
  (if (> a b) a b))

;; FIXED: Generate pseudo-random number using block data and user context
(define-private (generate-random-seed (user principal) (token-id uint))
  (let ((combined-data (concat (concat (unwrap-panic (to-consensus-buff? user))
                                       (unwrap-panic (to-consensus-buff? token-id)))
                               (unwrap-panic (to-consensus-buff? block-height)))))
    (let ((hash-result (keccak256 combined-data)))
      (let ((hash-16 (unwrap-panic (as-max-len? (unwrap-panic (slice? hash-result u0 u16)) u16))))
        (mod (buff-to-uint-be hash-16) u999999)))))

;; FIXED: Helper function to create token URI with length validation
(define-private (create-token-uri (token-id uint))
  (let ((base (var-get base-uri))
        (id-str (int-to-ascii token-id)))
    (let ((combined-length (+ (len base) (len id-str))))
      (if (<= combined-length u256)
          (some (concat base id-str))
          (some base))))) ;; Fallback to just base URI if too long

;; Enhanced rarity calculation with generation bonuses
(define-private (calculate-rarity-score (traits {background: uint, body: uint, eyes: uint, mouth: uint, accessory: uint}) (generation uint))
  (let ((bg-rarity (if (< (get background traits) u3) u50 u10))
        (body-rarity (if (< (get body traits) u2) u40 u10))
        (eyes-rarity (if (< (get eyes traits) u1) u100 u20))
        (mouth-rarity (if (< (get mouth traits) u2) u30 u5))
        (acc-rarity (if (< (get accessory traits) u1) u80 u15))
        (gen-bonus (* generation u25)))
    (+ bg-rarity body-rarity eyes-rarity mouth-rarity acc-rarity gen-bonus)))

;; Validate trait values are within acceptable ranges
(define-private (validate-traits (traits {background: uint, body: uint, eyes: uint, mouth: uint, accessory: uint}))
  (and (< (get background traits) max-traits-per-category)
       (< (get body traits) max-traits-per-category)  
       (< (get eyes traits) max-traits-per-category)
       (< (get mouth traits) max-traits-per-category)
       (< (get accessory traits) max-traits-per-category)))

;; Update user's owned tokens list
(define-private (add-token-to-owner (owner principal) (token-id uint))
  (let ((current-tokens (default-to (list) (map-get? owned-tokens owner))))
    (begin
      (map-set owned-tokens owner (unwrap! (as-max-len? (append current-tokens token-id) u50) (err u999)))
      (ok true))))

;; Generate evolved traits based on current traits and randomness
(define-private (evolve-traits (current-traits {background: uint, body: uint, eyes: uint, mouth: uint, accessory: uint}) (evolution-seed uint))
  (let ((mutation-chance (mod evolution-seed u100)))
    {
      background: (if (< mutation-chance u20) (mod (+ (get background current-traits) u1) max-traits-per-category) (get background current-traits)),
      body: (if (< (mod (/ evolution-seed u10) u100) u25) (mod (+ (get body current-traits) u1) max-traits-per-category) (get body current-traits)),
      eyes: (if (< (mod (/ evolution-seed u100) u100) u15) (mod (+ (get eyes current-traits) u1) max-traits-per-category) (get eyes current-traits)),
      mouth: (if (< (mod (/ evolution-seed u1000) u100) u30) (mod (+ (get mouth current-traits) u1) max-traits-per-category) (get mouth current-traits)),
      accessory: (if (< (mod (/ evolution-seed u10000) u100) u10) (mod (+ (get accessory current-traits) u1) max-traits-per-category) (get accessory current-traits))
    }))

;; Breed traits from two parent NFTs
(define-private (breed-traits (parent-one-traits {background: uint, body: uint, eyes: uint, mouth: uint, accessory: uint}) 
                             (parent-two-traits {background: uint, body: uint, eyes: uint, mouth: uint, accessory: uint}) 
                             (breeding-seed uint))
  {
    background: (if (< (mod breeding-seed u2) u1) (get background parent-one-traits) (get background parent-two-traits)),
    body: (if (< (mod (/ breeding-seed u10) u2) u1) (get body parent-one-traits) (get body parent-two-traits)),
    eyes: (if (< (mod (/ breeding-seed u100) u2) u1) (get eyes parent-one-traits) (get eyes parent-two-traits)),
    mouth: (if (< (mod (/ breeding-seed u1000) u2) u1) (get mouth parent-one-traits) (get mouth parent-two-traits)),
    accessory: (if (< (mod (/ breeding-seed u10000) u2) u1) (get accessory parent-one-traits) (get accessory parent-two-traits))
  })

;; Public read-only functions for contract state and NFT information

;; Get the last minted token ID
(define-read-only (get-last-token-id)
  (ok (- (var-get next-token-id) u1)))

;; Get token URI for metadata
(define-read-only (get-token-uri (token-id uint))
  (ok (map-get? token-uris token-id)))

;; Get token owner
(define-read-only (get-owner (token-id uint))
  (ok (map-get? token-owners token-id)))

;; Get NFT traits for a specific token
(define-read-only (get-nft-traits (token-id uint))
  (ok (map-get? nft-traits token-id)))

;; Get contract statistics
(define-read-only (get-contract-stats)
  (ok {
    total-minted: (var-get total-minted),
    total-evolved: (var-get total-evolved),
    total-bred: (var-get total-bred),
    next-token-id: (var-get next-token-id),
    contract-paused: (var-get contract-paused)
  }))

;; Get evolution history for a token
(define-read-only (get-evolution-history (token-id uint))
  (ok (default-to (list) (map-get? evolution-history token-id))))

;; Check if token can evolve (cooldown check)
(define-read-only (can-evolve (token-id uint))
  (let ((last-evolution (default-to u0 (map-get? last-evolution-block token-id))))
    (ok (>= (- block-height last-evolution) evolution-cooldown-blocks))))

;; Public functions for NFT operations and contract management

;; Transfer token between users (SIP-009 compliance)
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (or (is-eq tx-sender sender) (is-eq tx-sender contract-owner)) err-not-token-owner)
    (asserts! (is-eq (unwrap! (map-get? token-owners token-id) err-not-token-owner) sender) err-not-token-owner)
    (map-set token-owners token-id recipient)
    (ok true)))

;; Emergency pause/unpause contract (owner only)
(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))))

;; Toggle evolution feature (owner only)
(define-public (toggle-evolution)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set evolution-enabled (not (var-get evolution-enabled)))
    (ok (var-get evolution-enabled))))

;; Toggle breeding feature (owner only)
(define-public (toggle-breeding)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set breeding-enabled (not (var-get breeding-enabled)))
    (ok (var-get breeding-enabled))))

;; Evolve an existing NFT with new traits and enhanced rarity
(define-public (evolve-nft (token-id uint))
  (let ((current-traits-data (unwrap! (map-get? nft-traits token-id) err-invalid-trait))
        (token-owner (unwrap! (map-get? token-owners token-id) err-not-token-owner)))
    
    ;; Validate evolution conditions
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (var-get evolution-enabled) err-evolution-cooldown)
    (asserts! (is-eq tx-sender token-owner) err-not-token-owner)
    (asserts! (>= (stx-get-balance tx-sender) evolution-price) err-insufficient-balance)
    (asserts! (< (get generation current-traits-data) max-generation) err-invalid-generation)
    (asserts! (unwrap! (can-evolve token-id) err-evolution-cooldown) err-evolution-cooldown)
    
    ;; Generate evolution seed and new traits
    (let ((evolution-seed (generate-random-seed tx-sender (+ token-id block-height)))
          (current-base-traits {
            background: (get background current-traits-data),
            body: (get body current-traits-data),
            eyes: (get eyes current-traits-data),
            mouth: (get mouth current-traits-data),
            accessory: (get accessory current-traits-data)
          }))
      
      (let ((evolved-traits (evolve-traits current-base-traits evolution-seed))
            (new-generation (+ (get generation current-traits-data) u1))
            (new-rarity (calculate-rarity-score evolved-traits new-generation)))
        
        ;; Process evolution payment
        (try! (stx-transfer? evolution-price tx-sender contract-owner))
        
        ;; Update NFT with evolved traits
        (map-set nft-traits token-id (merge current-traits-data {
          background: (get background evolved-traits),
          body: (get body evolved-traits),
          eyes: (get eyes evolved-traits),
          mouth: (get mouth evolved-traits),
          accessory: (get accessory evolved-traits),
          rarity-score: new-rarity,
          generation: new-generation,
          evolution-count: (+ (get evolution-count current-traits-data) u1)
        }))
        
        ;; Update evolution tracking
        (map-set last-evolution-block token-id block-height)
        (let ((current-history (default-to (list) (map-get? evolution-history token-id))))
          (map-set evolution-history token-id 
            (unwrap! (as-max-len? (append current-history block-height) u10) (err u999))))
        
        ;; Update global counter
        (var-set total-evolved (+ (var-get total-evolved) u1))
        
        (ok {token-id: token-id, new-traits: evolved-traits, new-rarity: new-rarity, generation: new-generation})))))

;; Advanced breeding function to create offspring from two parent NFTs
;; This function combines traits from two parent NFTs using genetic algorithms
;; to create unique offspring with inherited characteristics and potential mutations
(define-public (breed-nfts (parent-one-id uint) (parent-two-id uint) (recipient principal))
  (let ((parent-one-data (unwrap! (map-get? nft-traits parent-one-id) err-invalid-trait))
        (parent-two-data (unwrap! (map-get? nft-traits parent-two-id) err-invalid-trait))
        (parent-one-owner (unwrap! (map-get? token-owners parent-one-id) err-not-token-owner))
        (parent-two-owner (unwrap! (map-get? token-owners parent-two-id) err-not-token-owner))
        (token-id (var-get next-token-id)))
    
    ;; Validate breeding conditions and permissions
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (var-get breeding-enabled) err-breeding-failed)
    (asserts! (<= token-id collection-limit) err-mint-limit-exceeded)
    (asserts! (>= (stx-get-balance tx-sender) breeding-price) err-insufficient-balance)
    (asserts! (or (is-eq tx-sender parent-one-owner) (is-eq tx-sender parent-two-owner)) err-not-token-owner)
    (asserts! (not (is-eq parent-one-id parent-two-id)) err-breeding-failed)
    
    ;; Generate breeding seed and create offspring traits
    (let ((breeding-seed (generate-random-seed recipient (+ parent-one-id parent-two-id token-id)))
          (parent-one-base-traits {
            background: (get background parent-one-data),
            body: (get body parent-one-data),
            eyes: (get eyes parent-one-data),
            mouth: (get mouth parent-one-data),
            accessory: (get accessory parent-one-data)
          })
          (parent-two-base-traits {
            background: (get background parent-two-data),
            body: (get body parent-two-data),
            eyes: (get eyes parent-two-data),
            mouth: (get mouth parent-two-data),
            accessory: (get accessory parent-two-data)
          }))
      
      (let ((offspring-traits (breed-traits parent-one-base-traits parent-two-base-traits breeding-seed))
            (offspring-generation (+ (max-uint (get generation parent-one-data) (get generation parent-two-data)) u1))
            (offspring-rarity (calculate-rarity-score offspring-traits offspring-generation)))
        
        ;; Validate offspring traits and generation limits
        (asserts! (validate-traits offspring-traits) err-invalid-trait)
        (asserts! (<= offspring-generation max-generation) err-invalid-generation)
        
        ;; Process breeding payment
        (try! (stx-transfer? breeding-price tx-sender contract-owner))
        
        ;; Create offspring NFT with combined genetics
        (let ((offspring-data {
                background: (get background offspring-traits),
                body: (get body offspring-traits),
                eyes: (get eyes offspring-traits),
                mouth: (get mouth offspring-traits),
                accessory: (get accessory offspring-traits),
                rarity-score: offspring-rarity,
                generation-seed: breeding-seed,
                generation: offspring-generation,
                birth-block: block-height,
                evolution-count: u0,
                parent-one: (some parent-one-id),
                parent-two: (some parent-two-id)
              }))
          
          ;; Store offspring data and update ownership
          (map-set token-owners token-id recipient)
          (map-set nft-traits token-id offspring-data)
          ;; FIXED: Use helper function to ensure proper URI length
          (map-set token-uris token-id (create-token-uri token-id))
          (map-set breeding-pairs {parent-one: parent-one-id, parent-two: parent-two-id} token-id)
          (try! (add-token-to-owner recipient token-id))
          
          ;; Update global counters
          (var-set next-token-id (+ token-id u1))
          (var-set total-minted (+ (var-get total-minted) u1))
          (var-set total-bred (+ (var-get total-bred) u1))
          
          ;; Return breeding success with offspring details
          (ok {
            token-id: token-id, 
            traits: offspring-traits, 
            rarity: offspring-rarity, 
            generation: offspring-generation,
            parents: {parent-one: parent-one-id, parent-two: parent-two-id}
          }))))))

;; Advanced mint function with algorithmic trait generation
(define-public (mint-dynamic-nft (recipient principal))
  (let ((token-id (var-get next-token-id))
        (generation-seed (generate-random-seed recipient token-id)))
    
    ;; Validate contract state and minting conditions
    (asserts! (not (var-get contract-paused)) err-contract-paused)
    (asserts! (<= token-id collection-limit) err-mint-limit-exceeded)
    (asserts! (>= (stx-get-balance tx-sender) mint-price) err-insufficient-balance)
    
    ;; Generate traits using algorithmic randomization
    (let ((bg-trait (mod (/ generation-seed u1000) max-traits-per-category))
          (body-trait (mod (/ generation-seed u100) max-traits-per-category))  
          (eyes-trait (mod (/ generation-seed u10) max-traits-per-category))
          (mouth-trait (mod generation-seed max-traits-per-category))
          (acc-trait (mod (+ generation-seed block-height) max-traits-per-category)))
      
      ;; Create trait map with generated values
      (let ((generated-traits {
              background: bg-trait,
              body: body-trait,
              eyes: eyes-trait, 
              mouth: mouth-trait,
              accessory: acc-trait
            }))
        
        ;; Validate generated traits and calculate rarity
        (asserts! (validate-traits generated-traits) err-invalid-trait)
        (let ((rarity (calculate-rarity-score generated-traits u1))
              (final-traits {
                background: bg-trait,
                body: body-trait,
                eyes: eyes-trait,
                mouth: mouth-trait,
                accessory: acc-trait,
                rarity-score: rarity,
                generation-seed: generation-seed,
                generation: u1,
                birth-block: block-height,
                evolution-count: u0,
                parent-one: none,
                parent-two: none
              }))
          
          ;; Execute mint transaction with payment processing
          (try! (stx-transfer? mint-price tx-sender contract-owner))
          
          ;; Store NFT data and update contract state
          (map-set token-owners token-id recipient)
          (map-set nft-traits token-id final-traits)
          ;; FIXED: Use helper function to ensure proper URI length
          (map-set token-uris token-id (create-token-uri token-id))
          (try! (add-token-to-owner recipient token-id))
          
          ;; Update global counters
          (var-set next-token-id (+ token-id u1))
          (var-set total-minted (+ (var-get total-minted) u1))
          
          ;; Return success with token details
          (ok {token-id: token-id, traits: generated-traits, rarity: rarity}))))))


