;; Neighborhood Watch DAO - Community-governed security and safety reporting system
;; A decentralized autonomous organization for community safety management

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-input (err u103))
(define-constant err-already-voted (err u104))
(define-constant err-proposal-expired (err u105))
(define-constant err-insufficient-stake (err u106))
(define-constant err-report-exists (err u107))
(define-constant err-invalid-status (err u108))

;; Data Variables
(define-data-var next-report-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var min-stake-amount uint u1000000) ;; 1 STX minimum stake
(define-data-var voting-period uint u1440) ;; 24 hours in blocks (assuming 1 min/block)
(define-data-var quorum-threshold uint u30) ;; 30% participation required

;; Data Maps
(define-map community-members principal 
  {
    stake-amount: uint,
    reputation-score: uint,
    join-block: uint,
    is-active: bool
  })

(define-map incident-reports uint
  {
    reporter: principal,
    location-hash: (buff 32),
    incident-type: (string-ascii 50),
    description: (string-ascii 500),
    timestamp: uint,
    severity-level: uint, ;; 1-5 scale
    status: (string-ascii 20), ;; "pending", "verified", "resolved", "dismissed"
    verification-count: uint,
    reward-amount: uint
  })

(define-map report-verifications {report-id: uint, verifier: principal}
  {
    verification-type: (string-ascii 20), ;; "support", "dispute"
    timestamp: uint,
    evidence-hash: (optional (buff 32))
  })

(define-map governance-proposals uint
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposal-type: (string-ascii 30), ;; "parameter-change", "emergency-response", "budget-allocation"
    voting-end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    total-stake-voted: uint,
    status: (string-ascii 20), ;; "active", "passed", "rejected", "executed"
    execution-block: (optional uint)
  })

(define-map proposal-votes {proposal-id: uint, voter: principal}
  {
    vote: bool, ;; true for yes, false for no
    stake-amount: uint,
    timestamp: uint
  })

(define-map emergency-contacts uint
  {
    contact-type: (string-ascii 30), ;; "police", "fire", "medical", "security"
    contact-info: (string-ascii 100),
    coverage-area: (string-ascii 100),
    is-verified: bool,
    added-by: principal
  })

;; Public Functions

;; Member Management
(define-public (join-community (stake-amount uint))
  (begin
    (asserts! (>= stake-amount (var-get min-stake-amount)) err-insufficient-stake)
    (asserts! (is-none (map-get? community-members tx-sender)) err-unauthorized)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Add member
    (map-set community-members tx-sender
      {
        stake-amount: stake-amount,
        reputation-score: u100, ;; Starting reputation
        join-block: block-height,
        is-active: true
      })
    (ok true)))

(define-public (increase-stake (additional-amount uint))
  (let ((member-data (unwrap! (map-get? community-members tx-sender) err-not-found)))
    (try! (stx-transfer? additional-amount tx-sender (as-contract tx-sender)))
    (map-set community-members tx-sender
      (merge member-data {stake-amount: (+ (get stake-amount member-data) additional-amount)}))
    (ok true)))

;; Incident Reporting
(define-public (submit-incident-report 
  (location-hash (buff 32))
  (incident-type (string-ascii 50))
  (description (string-ascii 500))
  (severity-level uint))
  (let ((report-id (var-get next-report-id))
        (member-data (unwrap! (map-get? community-members tx-sender) err-unauthorized)))
    
    (asserts! (get is-active member-data) err-unauthorized)
    (asserts! (<= severity-level u5) err-invalid-input)
    (asserts! (>= severity-level u1) err-invalid-input)
    
    (map-set incident-reports report-id
      {
        reporter: tx-sender,
        location-hash: location-hash,
        incident-type: incident-type,
        description: description,
        timestamp: block-height,
        severity-level: severity-level,
        status: "pending",
        verification-count: u0,
        reward-amount: (* severity-level u100000) ;; Reward based on severity
      })
    
    (var-set next-report-id (+ report-id u1))
    (ok report-id)))

(define-public (verify-report 
  (report-id uint)
  (verification-type (string-ascii 20))
  (evidence-hash (optional (buff 32))))
  (let ((report-data (unwrap! (map-get? incident-reports report-id) err-not-found))
        (member-data (unwrap! (map-get? community-members tx-sender) err-unauthorized)))
    
    (asserts! (get is-active member-data) err-unauthorized)
    (asserts! (is-none (map-get? report-verifications {report-id: report-id, verifier: tx-sender})) err-already-voted)
    (asserts! (or (is-eq verification-type "support") (is-eq verification-type "dispute")) err-invalid-input)
    
    ;; Record verification
    (map-set report-verifications {report-id: report-id, verifier: tx-sender}
      {
        verification-type: verification-type,
        timestamp: block-height,
        evidence-hash: evidence-hash
      })
    
    ;; Update report verification count
    (map-set incident-reports report-id
      (merge report-data {verification-count: (+ (get verification-count report-data) u1)}))
    
    (ok true)))

;; Governance Functions
(define-public (create-proposal
  (title (string-ascii 100))
  (description (string-ascii 500))
  (proposal-type (string-ascii 30)))
  (let ((proposal-id (var-get next-proposal-id))
        (member-data (unwrap! (map-get? community-members tx-sender) err-unauthorized)))
    
    (asserts! (get is-active member-data) err-unauthorized)
    (asserts! (>= (get stake-amount member-data) (* (var-get min-stake-amount) u5)) err-insufficient-stake)
    
    (map-set governance-proposals proposal-id
      {
        proposer: tx-sender,
        title: title,
        description: description,
        proposal-type: proposal-type,
        voting-end-block: (+ block-height (var-get voting-period)),
        yes-votes: u0,
        no-votes: u0,
        total-stake-voted: u0,
        status: "active",
        execution-block: none
      })
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)))

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
  (let ((proposal-data (unwrap! (map-get? governance-proposals proposal-id) err-not-found))
        (member-data (unwrap! (map-get? community-members tx-sender) err-unauthorized)))
    
    (asserts! (get is-active member-data) err-unauthorized)
    (asserts! (is-eq (get status proposal-data) "active") err-invalid-status)
    (asserts! (<= block-height (get voting-end-block proposal-data)) err-proposal-expired)
    (asserts! (is-none (map-get? proposal-votes {proposal-id: proposal-id, voter: tx-sender})) err-already-voted)
    
    ;; Record vote
    (map-set proposal-votes {proposal-id: proposal-id, voter: tx-sender}
      {
        vote: vote,
        stake-amount: (get stake-amount member-data),
        timestamp: block-height
      })
    
    ;; Update proposal vote counts
    (map-set governance-proposals proposal-id
      (merge proposal-data
        {
          yes-votes: (if vote (+ (get yes-votes proposal-data) u1) (get yes-votes proposal-data)),
          no-votes: (if vote (get no-votes proposal-data) (+ (get no-votes proposal-data) u1)),
          total-stake-voted: (+ (get total-stake-voted proposal-data) (get stake-amount member-data))
        }))
    
    (ok true)))

;; Emergency Response
(define-public (add-emergency-contact
  (contact-type (string-ascii 30))
  (contact-info (string-ascii 100))
  (coverage-area (string-ascii 100)))
  (let ((contact-id (var-get next-report-id))
        (member-data (unwrap! (map-get? community-members tx-sender) err-unauthorized)))
    
    (asserts! (get is-active member-data) err-unauthorized)
    (asserts! (>= (get reputation-score member-data) u150) err-unauthorized)
    
    (map-set emergency-contacts contact-id
      {
        contact-type: contact-type,
        contact-info: contact-info,
        coverage-area: coverage-area,
        is-verified: false,
        added-by: tx-sender
      })
    
    (ok contact-id)))

;; Admin Functions
(define-public (update-report-status (report-id uint) (new-status (string-ascii 20)))
  (let ((report-data (unwrap! (map-get? incident-reports report-id) err-not-found))
        (member-data (unwrap! (map-get? community-members tx-sender) err-unauthorized)))
    
    (asserts! (>= (get reputation-score member-data) u200) err-unauthorized)
    (asserts! (get is-active member-data) err-unauthorized)
    
    (map-set incident-reports report-id
      (merge report-data {status: new-status}))
    
    ;; If report is verified, reward the reporter
    (if (is-eq new-status "verified")
      (let ((reward-amount (get reward-amount report-data)))
        (try! (as-contract (stx-transfer? reward-amount tx-sender (get reporter report-data))))
        (ok true))
      (ok true))))

(define-public (finalize-proposal (proposal-id uint))
  (let ((proposal-data (unwrap! (map-get? governance-proposals proposal-id) err-not-found)))
    
    (asserts! (is-eq (get status proposal-data) "active") err-invalid-status)
    (asserts! (> block-height (get voting-end-block proposal-data)) err-proposal-expired)
    
    (let ((total-members (get-total-active-members))
          (participation-rate (* (+ (get yes-votes proposal-data) (get no-votes proposal-data)) u100))
          (quorum-met (>= participation-rate (* total-members (var-get quorum-threshold))))
          (proposal-passed (and quorum-met (> (get yes-votes proposal-data) (get no-votes proposal-data)))))
      
      (map-set governance-proposals proposal-id
        (merge proposal-data
          {
            status: (if proposal-passed "passed" "rejected"),
            execution-block: (if proposal-passed (some block-height) none)
          }))
      
      (ok proposal-passed))))

;; Read-only Functions
(define-read-only (get-member-info (member principal))
  (map-get? community-members member))

(define-read-only (get-report-details (report-id uint))
  (map-get? incident-reports report-id))

(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? governance-proposals proposal-id))

(define-read-only (get-emergency-contact (contact-id uint))
  (map-get? emergency-contacts contact-id))

(define-read-only (get-total-active-members)
  ;; This is a simplified implementation
  ;; In practice, you'd iterate through all members
  u100) ;; Placeholder value

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))

(define-read-only (get-voting-power (member principal))
  (match (map-get? community-members member)
    member-data (get stake-amount member-data)
    u0))

;; Initialize contract
(begin
  (var-set next-report-id u1)
  (var-set next-proposal-id u1))