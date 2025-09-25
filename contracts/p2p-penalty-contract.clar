;; p2p-penalty-contract
;; A decentralized penalty resolution and escrow management system on the Stacks blockchain
;; This contract facilitates secure, trustless penalty and compensation agreements

;; Error codes for precise error handling
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PENALTY-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PENALTY (err u102))
(define-constant ERR-ALREADY-RESOLVED (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))
(define-constant ERR-DISPUTE-EXISTS (err u105))
(define-constant ERR-NO-DISPUTE (err u106))
(define-constant ERR-UNAUTHORIZED-MEDIATOR (err u107))

;; Penalty status constants
(define-constant STATUS-PENDING u1)
(define-constant STATUS-ACCEPTED u2)
(define-constant STATUS-DISPUTED u3)
(define-constant STATUS-RESOLVED u4)
(define-constant STATUS-CANCELLED u5)

;; Dispute resolution status
(define-constant DISPUTE-OPEN u1)
(define-constant DISPUTE-CLOSED u2)

;; Data maps for managing penalties and disputes
(define-map penalty-agreements
  { penalty-id: uint }
  {
    initiator: principal,
    respondent: principal,
    amount: uint,
    reason: (string-utf8 500),
    status: uint,
    created-at: uint,
    resolved-at: (optional uint)
  }
)

(define-map penalty-disputes
  { penalty-id: uint }
  {
    filed-by: principal,
    reason: (string-utf8 500),
    evidence: (string-utf8 500),
    mediator: (optional principal),
    resolution: (optional (string-utf8 500)),
    status: uint,
    created-at: uint
  }
)

(define-map authorized-mediators principal bool)

;; Counters and variables
(define-data-var penalty-id-counter uint u1)
(define-data-var contract-owner principal tx-sender)
(define-data-var mediation-fee-bps uint u250) ;; 2.5% default fee

;; Private helper functions
(define-private (generate-penalty-id)
  (let ((current-id (var-get penalty-id-counter)))
    (var-set penalty-id-counter (+ current-id u1))
    current-id
  )
)

(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-authorized-mediator)
  (default-to false (map-get? authorized-mediators tx-sender))
)

(define-private (calculate-mediation-fee (amount uint))
  (/ (* amount (var-get mediation-fee-bps)) u10000)
)

;; Read-only functions for retrieving information
(define-read-only (get-penalty-details (penalty-id uint))
  (map-get? penalty-agreements { penalty-id: penalty-id })
)

(define-read-only (get-dispute-details (penalty-id uint))
  (map-get? penalty-disputes { penalty-id: penalty-id })
)

;; Public functions for penalty management
(define-public (create-penalty-agreement
  (respondent principal)
  (amount uint)
  (reason (string-utf8 500))
)
  (let ((new-penalty-id (generate-penalty-id)))
    (asserts! (> amount u0) ERR-INVALID-PENALTY)
    (asserts! (not (is-eq tx-sender respondent)) ERR-NOT-AUTHORIZED)
    
    ;; Transfer penalty amount to contract
    (unwrap! (stx-transfer? amount tx-sender (as-contract tx-sender)) ERR-INSUFFICIENT-FUNDS)
    
    ;; Create penalty agreement
    (map-set penalty-agreements
      { penalty-id: new-penalty-id }
      {
        initiator: tx-sender,
        respondent: respondent,
        amount: amount,
        reason: reason,
        status: STATUS-PENDING,
        created-at: block-height,
        resolved-at: none
      }
    )
    
    (ok new-penalty-id)
  )
)

(define-public (accept-penalty (penalty-id uint))
  (let ((penalty (unwrap! (map-get? penalty-agreements { penalty-id: penalty-id }) ERR-PENALTY-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get respondent penalty)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status penalty) STATUS-PENDING) ERR-INVALID-PENALTY)
    
    ;; Update penalty status to accepted
    (map-set penalty-agreements
      { penalty-id: penalty-id }
      (merge penalty { 
        status: STATUS-ACCEPTED, 
        resolved-at: (some block-height) 
      })
    )
    
    ;; Transfer funds to initiator
    (as-contract
      (unwrap! (stx-transfer? (get amount penalty) tx-sender (get initiator penalty)) ERR-INSUFFICIENT-FUNDS)
    )
    
    (ok true)
  )
)

(define-public (file-dispute 
  (penalty-id uint)
  (reason (string-utf8 500))
  (evidence (string-utf8 500))
)
  (let ((penalty (unwrap! (map-get? penalty-agreements { penalty-id: penalty-id }) ERR-PENALTY-NOT-FOUND)))
    (asserts! (or (is-eq tx-sender (get initiator penalty)) (is-eq tx-sender (get respondent penalty))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status penalty) STATUS-PENDING) ERR-INVALID-PENALTY)
    (asserts! (is-none (map-get? penalty-disputes { penalty-id: penalty-id })) ERR-DISPUTE-EXISTS)
    
    ;; Create dispute record
    (map-set penalty-disputes
      { penalty-id: penalty-id }
      {
        filed-by: tx-sender,
        reason: reason,
        evidence: evidence,
        mediator: none,
        resolution: none,
        status: DISPUTE-OPEN,
        created-at: block-height
      }
    )
    
    ;; Update penalty status
    (map-set penalty-agreements
      { penalty-id: penalty-id }
      (merge penalty { status: STATUS-DISPUTED })
    )
    
    (ok true)
  )
)

(define-public (resolve-dispute 
  (penalty-id uint)
  (resolution (string-utf8 500))
  (initiator-refund-percent uint)
)
  (let (
    (dispute (unwrap! (map-get? penalty-disputes { penalty-id: penalty-id }) ERR-NO-DISPUTE))
    (penalty (unwrap! (map-get? penalty-agreements { penalty-id: penalty-id }) ERR-PENALTY-NOT-FOUND))
    (total-amount (get amount penalty))
    (initiator-refund (/ (* total-amount initiator-refund-percent) u100))
    (respondent-amount (- total-amount initiator-refund))
  )
    ;; Only authorized mediators can resolve
    (asserts! (is-authorized-mediator) ERR-UNAUTHORIZED-MEDIATOR)
    (asserts! (is-eq (get status dispute) DISPUTE-OPEN) ERR-INVALID-PENALTY)
    (asserts! (<= initiator-refund-percent u100) ERR-INVALID-PENALTY)
    
    ;; Update dispute with resolution
    (map-set penalty-disputes
      { penalty-id: penalty-id }
      (merge dispute {
        mediator: (some tx-sender),
        resolution: (some resolution),
        status: DISPUTE-CLOSED
      })
    )
    
    ;; Distribute funds based on resolution
    (as-contract
      (begin
        (if (> initiator-refund u0)
          (unwrap! (stx-transfer? initiator-refund tx-sender (get initiator penalty)) ERR-INSUFFICIENT-FUNDS)
          true
        )
        (if (> respondent-amount u0)
          (unwrap! (stx-transfer? respondent-amount tx-sender (get respondent penalty)) ERR-INSUFFICIENT-FUNDS)
          true
        )
      )
    )
    
    ;; Update penalty status
    (map-set penalty-agreements
      { penalty-id: penalty-id }
      (merge penalty { 
        status: STATUS-RESOLVED,
        resolved-at: (some block-height)
      })
    )
    
    (ok true)
  )
)

;; Administrative functions
(define-public (update-mediation-fee (new-fee-bps uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee-bps u1000) ERR-INVALID-PENALTY) ;; Max 10%
    (var-set mediation-fee-bps new-fee-bps)
    (ok true)
  )
)

(define-public (add-mediator (mediator principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set authorized-mediators mediator true)
    (ok true)
  )
)

(define-public (remove-mediator (mediator principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-delete authorized-mediators mediator)
    (ok true)
  )
)

(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)