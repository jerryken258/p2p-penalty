;; fairnest-marketplace
;; A decentralized rental marketplace that connects landlords and tenants in a trustless environment
;; This contract manages property listings, rental agreements, payments, dispute resolution, and a reputation system

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-LISTING-NOT-FOUND (err u101))
(define-constant ERR-INVALID-LISTING (err u102))
(define-constant ERR-ALREADY-LISTED (err u103))
(define-constant ERR-ALREADY-RENTED (err u104))
(define-constant ERR-NOT-AVAILABLE (err u105))
(define-constant ERR-AGREEMENT-NOT-FOUND (err u106))
(define-constant ERR-INSUFFICIENT-FUNDS (err u107))
(define-constant ERR-ALREADY-PAID (err u108))
(define-constant ERR-NOT-DUE (err u109))
(define-constant ERR-DISPUTE-EXISTS (err u110))
(define-constant ERR-NO-DISPUTE (err u111))
(define-constant ERR-INVALID-STATE (err u112))
(define-constant ERR-UNAUTHORIZED-ARBITER (err u113))
(define-constant ERR-NOT-TENANT (err u114))
(define-constant ERR-NOT-LANDLORD (err u115))
(define-constant ERR-INVALID-RATING (err u116))
(define-constant ERR-ALREADY-RATED (err u117))
(define-constant ERR-AGREEMENT-ACTIVE (err u118))

;; Listing status options
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-RENTED u2)
(define-constant STATUS-INACTIVE u3)

;; Agreement status options
(define-constant AGREEMENT-PENDING u1)
(define-constant AGREEMENT-ACTIVE u2)
(define-constant AGREEMENT-COMPLETED u3)
(define-constant AGREEMENT-TERMINATED u4)
(define-constant AGREEMENT-DISPUTED u5)

;; Dispute status options
(define-constant DISPUTE-OPEN u1)
(define-constant DISPUTE-RESOLVED u2)

;; Data maps

;; Stores property listing information
(define-map property-listings
  { listing-id: uint }
  {
    owner: principal,
    title: (string-utf8 100),
    description: (string-utf8 500),
    location: (string-utf8 100),
    price-per-month: uint,
    deposit-amount: uint,
    min-rental-period: uint,
    max-rental-period: uint,
    amenities: (list 20 (string-utf8 30)),
    status: uint,
    created-at: uint
  }
)

;; Stores rental agreements between landlords and tenants
(define-map rental-agreements
  { agreement-id: uint }
  {
    listing-id: uint,
    landlord: principal,
    tenant: principal,
    start-date: uint,
    end-date: uint,
    monthly-rent: uint,
    deposit-amount: uint,
    payment-due-day: uint,
    status: uint,
    last-payment-date: uint,
    created-at: uint
  }
)

;; Maps agreement IDs to their payment histories
(define-map payment-histories
  { agreement-id: uint }
  { payments: (list 100 { amount: uint, payment-date: uint, payment-type: (string-utf8 20), confirmer: principal }) }
)

;; Tracks disputes filed for agreements
(define-map disputes
  { agreement-id: uint }
  {
    filed-by: principal,
    reason: (string-utf8 500),
    evidence: (string-utf8 100),
    resolution: (optional (string-utf8 500)),
    arbiter: (optional principal),
    status: uint,
    created-at: uint
  }
)

;; Maps users to their reputation scores and reviews
(define-map user-reputations
  { user: principal }
  {
    avg-rating: uint,
    total-ratings: uint,
    reviews: (list 100 { reviewer: principal, rating: uint, comment: (string-utf8 200), timestamp: uint })
  }
)

;; Contract administrators
(define-map administrators principal bool)

;; Authorized arbiters for dispute resolution
(define-map authorized-arbiters principal bool)

;; Counters for ID generation
(define-data-var listing-id-counter uint u1)
(define-data-var agreement-id-counter uint u1)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Fee percentage for the platform (in basis points - 100 = 1%)
(define-data-var platform-fee-bps uint u250) ;; 2.5% default fee

;; Private functions

;; Generate a new listing ID
(define-private (generate-listing-id)
  (let ((current-id (var-get listing-id-counter)))
    (var-set listing-id-counter (+ current-id u1))
    current-id
  )
)

;; Generate a new agreement ID
(define-private (generate-agreement-id)
  (let ((current-id (var-get agreement-id-counter)))
    (var-set agreement-id-counter (+ current-id u1))
    current-id
  )
)

;; Check if caller is the contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Check if caller is an administrator
(define-private (is-administrator)
  (default-to false (map-get? administrators tx-sender))
)

;; Check if caller is an authorized arbiter
(define-private (is-authorized-arbiter)
  (default-to false (map-get? authorized-arbiters tx-sender))
)

;; Calculate platform fee amount
(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-bps)) u10000)
)

;; Initialize a new user reputation if it doesn't exist
(define-private (initialize-user-reputation (user principal))
  (if (is-none (map-get? user-reputations { user: user }))
    (map-set user-reputations
      { user: user }
      {
        avg-rating: u0,
        total-ratings: u0,
        reviews: (list)
      }
    )
    true
  )
)

;; Add a payment record to the payment history
(define-private (add-payment-record (agreement-id uint) (amount uint) (payment-type (string-utf8 20)))
  (let (
    (current-history (default-to { payments: (list) } (map-get? payment-histories { agreement-id: agreement-id })))
    (new-payment { amount: amount, payment-date: block-height, payment-type: payment-type, confirmer: tx-sender })
  )
    (map-set payment-histories
      { agreement-id: agreement-id }
      {
        payments: (append (get payments current-history) new-payment)
      }
    )
  )
)

;; Calculate new average rating when adding a review
(define-private (calculate-new-average (current-avg uint) (current-count uint) (new-rating uint))
  (if (is-eq current-count u0)
    new-rating
    (/ (+ (* current-avg current-count) new-rating) (+ current-count u1))
  )
)

;; Read-only functions

;; Get listing details
(define-read-only (get-listing (listing-id uint))
  (map-get? property-listings { listing-id: listing-id })
)

;; Get all listings owned by a principal
(define-read-only (get-listings-by-owner (owner principal))
  (map-get? property-listings { owner: owner })
)

;; Get rental agreement details
(define-read-only (get-rental-agreement (agreement-id uint))
  (map-get? rental-agreements { agreement-id: agreement-id })
)

;; Get payment history for an agreement
(define-read-only (get-payment-history (agreement-id uint))
  (map-get? payment-histories { agreement-id: agreement-id })
)

;; Get dispute details
(define-read-only (get-dispute (agreement-id uint))
  (map-get? disputes { agreement-id: agreement-id })
)

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputations { user: user })
)

;; Check if a listing is available
(define-read-only (is-listing-available (listing-id uint))
  (match (map-get? property-listings { listing-id: listing-id })
    listing (is-eq (get status listing) STATUS-ACTIVE)
    false
  )
)

;; Public functions

;; Create a new property listing
(define-public (create-listing 
  (title (string-utf8 100))
  (description (string-utf8 500))
  (location (string-utf8 100))
  (price-per-month uint)
  (deposit-amount uint)
  (min-rental-period uint)
  (max-rental-period uint)
  (amenities (list 20 (string-utf8 30)))
)
  (let ((new-listing-id (generate-listing-id)))
    (asserts! (> price-per-month u0) ERR-INVALID-LISTING)
    (asserts! (>= max-rental-period min-rental-period) ERR-INVALID-LISTING)
    
    (map-set property-listings
      { listing-id: new-listing-id }
      {
        owner: tx-sender,
        title: title,
        description: description,
        location: location,
        price-per-month: price-per-month,
        deposit-amount: deposit-amount,
        min-rental-period: min-rental-period,
        max-rental-period: max-rental-period,
        amenities: amenities,
        status: STATUS-ACTIVE,
        created-at: block-height
      }
    )
    
    ;; Initialize owner reputation if not already done
    (initialize-user-reputation tx-sender)
    
    (ok new-listing-id)
  )
)

;; Update an existing property listing
(define-public (update-listing 
  (listing-id uint)
  (title (string-utf8 100))
  (description (string-utf8 500))
  (location (string-utf8 100))
  (price-per-month uint)
  (deposit-amount uint)
  (min-rental-period uint)
  (max-rental-period uint)
  (amenities (list 20 (string-utf8 30)))
)
  (let ((listing (unwrap! (map-get? property-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get owner listing)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status listing) STATUS-ACTIVE) ERR-INVALID-STATE)
    (asserts! (> price-per-month u0) ERR-INVALID-LISTING)
    (asserts! (>= max-rental-period min-rental-period) ERR-INVALID-LISTING)
    
    (map-set property-listings
      { listing-id: listing-id }
      (merge listing {
        title: title,
        description: description,
        location: location,
        price-per-month: price-per-month,
        deposit-amount: deposit-amount,
        min-rental-period: min-rental-period,
        max-rental-period: max-rental-period,
        amenities: amenities
      })
    )
    
    (ok true)
  )
)

;; Change the status of a listing (active, inactive)
(define-public (change-listing-status (listing-id uint) (new-status uint))
  (let ((listing (unwrap! (map-get? property-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get owner listing)) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq new-status STATUS-ACTIVE) (is-eq new-status STATUS-INACTIVE)) ERR-INVALID-STATE)
    ;; Cannot manually change to rented status - that's done by the agreement creation
    (asserts! (not (is-eq (get status listing) STATUS-RENTED)) ERR-ALREADY-RENTED)
    
    (map-set property-listings
      { listing-id: listing-id }
      (merge listing { status: new-status })
    )
    
    (ok true)
  )
)

;; Create a rental agreement application
(define-public (create-rental-agreement
  (listing-id uint)
  (start-date uint)
  (end-date uint)
  (deposit-stx uint)
)
  (let (
    (listing (unwrap! (map-get? property-listings { listing-id: listing-id }) ERR-LISTING-NOT-FOUND))
    (new-agreement-id (generate-agreement-id))
  )
    ;; Validate listing availability and agreement terms
    (asserts! (is-eq (get status listing) STATUS-ACTIVE) ERR-NOT-AVAILABLE)
    (asserts! (>= end-date start-date) ERR-INVALID-LISTING)
    (asserts! (>= (- end-date start-date) (get min-rental-period listing)) ERR-INVALID-LISTING)
    (asserts! (<= (- end-date start-date) (get max-rental-period listing)) ERR-INVALID-LISTING)
    (asserts! (not (is-eq tx-sender (get owner listing))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq deposit-stx (get deposit-amount listing)) ERR-INVALID-LISTING)
    
    ;; Transfer deposit to contract
    (unwrap! (stx-transfer? deposit-stx tx-sender (as-contract tx-sender)) ERR-INSUFFICIENT-FUNDS)
    
    ;; Create the rental agreement
    (map-set rental-agreements
      { agreement-id: new-agreement-id }
      {
        listing-id: listing-id,
        landlord: (get owner listing),
        tenant: tx-sender,
        start-date: start-date,
        end-date: end-date,
        monthly-rent: (get price-per-month listing),
        deposit-amount: deposit-stx,
        payment-due-day: u1, ;; Default to 1st day of each month
        status: AGREEMENT-ACTIVE,
        last-payment-date: block-height,
        created-at: block-height
      }
    )
    
    ;; Update listing status to rented
    (map-set property-listings
      { listing-id: listing-id }
      (merge listing { status: STATUS-RENTED })
    )
    
    ;; Initialize payment history
    (map-set payment-histories
      { agreement-id: new-agreement-id }
      { payments: (list { amount: deposit-stx, payment-date: block-height, payment-type: "deposit", confirmer: tx-sender }) }
    )
    
    ;; Initialize tenant reputation if not already done
    (initialize-user-reputation tx-sender)
    
    (ok new-agreement-id)
  )
)

;; Pay monthly rent
(define-public (pay-rent (agreement-id uint))
  (let (
    (agreement (unwrap! (map-get? rental-agreements { agreement-id: agreement-id }) ERR-AGREEMENT-NOT-FOUND))
    (rent-amount (get monthly-rent agreement))
    (platform-fee (calculate-platform-fee rent-amount))
    (landlord-amount (- rent-amount platform-fee))
  )
    ;; Validate payment
    (asserts! (is-eq tx-sender (get tenant agreement)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status agreement) AGREEMENT-ACTIVE) ERR-INVALID-STATE)
    
    ;; Transfer rent: part to landlord, part as platform fee
    (unwrap! (stx-transfer? landlord-amount tx-sender (get landlord agreement)) ERR-INSUFFICIENT-FUNDS)
    (unwrap! (stx-transfer? platform-fee tx-sender (var-get contract-owner)) ERR-INSUFFICIENT-FUNDS)
    
    ;; Update agreement with new payment date
    (map-set rental-agreements
      { agreement-id: agreement-id }
      (merge agreement { last-payment-date: block-height })
    )
    
    ;; Add to payment history
    (add-payment-record agreement-id rent-amount "rent")
    
    (ok true)
  )
)

;; Complete a rental agreement (normal end of term)
(define-public (complete-agreement (agreement-id uint))
  (let (
    (agreement (unwrap! (map-get? rental-agreements { agreement-id: agreement-id }) ERR-AGREEMENT-NOT-FOUND))
  )
    ;; Only landlord can mark as completed
    (asserts! (is-eq tx-sender (get landlord agreement)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status agreement) AGREEMENT-ACTIVE) ERR-INVALID-STATE)
    (asserts! (>= block-height (get end-date agreement)) ERR-AGREEMENT-ACTIVE)
    
    ;; Return deposit to tenant
    (as-contract
      (unwrap! (stx-transfer? (get deposit-amount agreement) tx-sender (get tenant agreement)) ERR-INSUFFICIENT-FUNDS)
    )
    
    ;; Update agreement status
    (map-set rental-agreements
      { agreement-id: agreement-id }
      (merge agreement { status: AGREEMENT-COMPLETED })
    )
    
    ;; Add deposit return to payment history
    (add-payment-record agreement-id (get deposit-amount agreement) "deposit-return")
    
    ;; Make listing available again
    (map-set property-listings
      { listing-id: (get listing-id agreement) }
      (merge (unwrap! (map-get? property-listings { listing-id: (get listing-id agreement) }) ERR-LISTING-NOT-FOUND)
        { status: STATUS-ACTIVE }
      )
    )
    
    (ok true)
  )
)

;; File a dispute for an agreement
(define-public (file-dispute 
  (agreement-id uint)
  (reason (string-utf8 500))
  (evidence (string-utf8 100))
)
  (let (
    (agreement (unwrap! (map-get? rental-agreements { agreement-id: agreement-id }) ERR-AGREEMENT-NOT-FOUND))
  )
    ;; Only landlord or tenant can file a dispute
    (asserts! (or (is-eq tx-sender (get landlord agreement)) (is-eq tx-sender (get tenant agreement))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status agreement) AGREEMENT-ACTIVE) ERR-INVALID-STATE)
    (asserts! (is-none (map-get? disputes { agreement-id: agreement-id })) ERR-DISPUTE-EXISTS)
    
    ;; Create the dispute record
    (map-set disputes
      { agreement-id: agreement-id }
      {
        filed-by: tx-sender,
        reason: reason,
        evidence: evidence,
        resolution: none,
        arbiter: none,
        status: DISPUTE-OPEN,
        created-at: block-height
      }
    )
    
    ;; Update agreement status
    (map-set rental-agreements
      { agreement-id: agreement-id }
      (merge agreement { status: AGREEMENT-DISPUTED })
    )
    
    (ok true)
  )
)

;; Resolve a dispute (by authorized arbiter)
(define-public (resolve-dispute 
  (agreement-id uint)
  (resolution (string-utf8 500))
  (tenant-refund-percent uint)
)
  (let (
    (dispute (unwrap! (map-get? disputes { agreement-id: agreement-id }) ERR-NO-DISPUTE))
    (agreement (unwrap! (map-get? rental-agreements { agreement-id: agreement-id }) ERR-AGREEMENT-NOT-FOUND))
    (deposit-amount (get deposit-amount agreement))
    (tenant-refund (/ (* deposit-amount tenant-refund-percent) u100))
    (landlord-amount (- deposit-amount tenant-refund))
  )
    ;; Only authorized arbiters can resolve disputes
    (asserts! (is-authorized-arbiter) ERR-UNAUTHORIZED-ARBITER)
    (asserts! (is-eq (get status dispute) DISPUTE-OPEN) ERR-INVALID-STATE)
    (asserts! (<= tenant-refund-percent u100) ERR-INVALID-LISTING)
    
    ;; Update dispute with resolution details
    (map-set disputes
      { agreement-id: agreement-id }
      (merge dispute {
        resolution: (some resolution),
        arbiter: (some tx-sender),
        status: DISPUTE-RESOLVED
      })
    )
    
    ;; Distribute deposit according to resolution
    (as-contract
      (begin
        (if (> tenant-refund u0)
          (unwrap! (stx-transfer? tenant-refund tx-sender (get tenant agreement)) ERR-INSUFFICIENT-FUNDS)
          true
        )
        (if (> landlord-amount u0)
          (unwrap! (stx-transfer? landlord-amount tx-sender (get landlord agreement)) ERR-INSUFFICIENT-FUNDS)
          true
        )
      )
    )
    
    ;; Update agreement status to terminated
    (map-set rental-agreements
      { agreement-id: agreement-id }
      (merge agreement { status: AGREEMENT-TERMINATED })
    )
    
    ;; Make listing available again
    (map-set property-listings
      { listing-id: (get listing-id agreement) }
      (merge (unwrap! (map-get? property-listings { listing-id: (get listing-id agreement) }) ERR-LISTING-NOT-FOUND)
        { status: STATUS-ACTIVE }
      )
    )
    
    ;; Add resolution payments to history
    (if (> tenant-refund u0)
      (add-payment-record agreement-id tenant-refund "dispute-tenant-refund")
      true
    )
    (if (> landlord-amount u0)
      (add-payment-record agreement-id landlord-amount "dispute-landlord-payment")
      true
    )
    
    (ok true)
  )
)

;; Rate a user after completed or terminated agreement
(define-public (rate-user 
  (agreement-id uint)
  (user-to-rate principal)
  (rating uint)
  (comment (string-utf8 200))
)
  (let (
    (agreement (unwrap! (map-get? rental-agreements { agreement-id: agreement-id }) ERR-AGREEMENT-NOT-FOUND))
    (user-reputation (default-to { avg-rating: u0, total-ratings: u0, reviews: (list) } 
                      (map-get? user-reputations { user: user-to-rate })))
    (current-avg (get avg-rating user-reputation))
    (current-count (get total-ratings user-reputation))
    (reviews (get reviews user-reputation))
  )
    ;; Validate the rating parameters
    (asserts! (or (is-eq (get status agreement) AGREEMENT-COMPLETED) (is-eq (get status agreement) AGREEMENT-TERMINATED)) ERR-INVALID-STATE)
    (asserts! (or (is-eq tx-sender (get landlord agreement)) (is-eq tx-sender (get tenant agreement))) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq user-to-rate (get landlord agreement)) (is-eq user-to-rate (get tenant agreement))) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq tx-sender user-to-rate)) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
    
    ;; Check if user has already been rated for this agreement
    (asserts! (is-none (find (lambda (review) (is-eq (get reviewer review) tx-sender)) reviews)) ERR-ALREADY-RATED)
    
    ;; Calculate new average rating
    (let (
      (new-avg (calculate-new-average current-avg current-count rating))
      (new-review { reviewer: tx-sender, rating: rating, comment: comment, timestamp: block-height })
    )
      ;; Update user reputation
      (map-set user-reputations
        { user: user-to-rate }
        {
          avg-rating: new-avg,
          total-ratings: (+ current-count u1),
          reviews: (append reviews new-review)
        }
      )
      
      (ok true)
    )
  )
)

;; Administrative functions

;; Update platform fee
(define-public (update-platform-fee (new-fee-bps uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee-bps u1000) ERR-INVALID-LISTING) ;; Max 10%
    (var-set platform-fee-bps new-fee-bps)
    (ok true)
  )
)

;; Add an administrator
(define-public (add-administrator (admin principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set administrators admin true)
    (ok true)
  )
)

;; Remove an administrator
(define-public (remove-administrator (admin principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-delete administrators admin)
    (ok true)
  )
)

;; Add an authorized arbiter
(define-public (add-arbiter (arbiter principal))
  (begin
    (asserts! (or (is-contract-owner) (is-administrator)) ERR-NOT-AUTHORIZED)
    (map-set authorized-arbiters arbiter true)
    (ok true)
  )
)

;; Remove an authorized arbiter
(define-public (remove-arbiter (arbiter principal))
  (begin
    (asserts! (or (is-contract-owner) (is-administrator)) ERR-NOT-AUTHORIZED)
    (map-delete authorized-arbiters arbiter)
    (ok true)
  )
)

;; Transfer contract ownership
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)