;; Flow Rate Documentation Contract
;; Records detailed water pressure and volume measurements

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-MEASUREMENT (err u201))
(define-constant ERR-TEST-NOT-FOUND (err u202))
(define-constant ERR-INVALID-INPUT (err u203))
(define-constant ERR-CALIBRATION-EXPIRED (err u204))

;; Data Variables
(define-data-var next-test-id uint u1)
(define-data-var calibration-interval uint u2592000) ;; 30 days in seconds

;; Data Maps
(define-map flow-test-results
  { test-id: uint }
  {
    hydrant-id: (string-ascii 20),
    test-date: uint,
    technician-id: (string-ascii 30),
    static-pressure: uint,
    residual-pressure: uint,
    flow-rate-gpm: uint,
    test-duration: uint,
    weather-conditions: (string-ascii 50),
    equipment-used: (string-ascii 100),
    test-status: (string-ascii 20),
    created-at: uint
  }
)

(define-map measurement-details
  { test-id: uint }
  {
    outlet-count: uint,
    outlet-sizes: (string-ascii 50),
    pressure-readings: (list 10 uint),
    flow-readings: (list 10 uint),
    temperature: uint,
    ph-level: uint,
    turbidity: uint,
    chlorine-level: uint,
    notes: (string-ascii 200)
  }
)

(define-map equipment-calibration
  { equipment-id: (string-ascii 30) }
  {
    last-calibration: uint,
    calibration-due: uint,
    accuracy-rating: uint,
    serial-number: (string-ascii 50),
    manufacturer: (string-ascii 50),
    model: (string-ascii 50),
    status: (string-ascii 20)
  }
)

(define-map authorized-technicians
  { technician-id: (string-ascii 30) }
  {
    name: (string-ascii 50),
    certification-level: (string-ascii 20),
    certification-expiry: uint,
    active: bool
  }
)

;; Authorization Functions
(define-private (is-authorized-technician (technician-id (string-ascii 30)))
  (match (map-get? authorized-technicians { technician-id: technician-id })
    tech-info
    (and
      (get active tech-info)
      (> (get certification-expiry tech-info) (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    false
  )
)

(define-private (is-equipment-calibrated (equipment-id (string-ascii 30)))
  (match (map-get? equipment-calibration { equipment-id: equipment-id })
    equipment
    (let
      (
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
        (calibration-due (get calibration-due equipment))
      )
      (and
        (is-eq (get status equipment) "active")
        (> calibration-due current-time)
      )
    )
    false
  )
)

;; Public Functions

;; Add authorized technician
(define-public (add-technician
  (technician-id (string-ascii 30))
  (name (string-ascii 50))
  (certification-level (string-ascii 20))
  (certification-expiry uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len technician-id) u0) ERR-INVALID-INPUT)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> certification-expiry (unwrap-panic (get-block-info? time (- block-height u1)))) ERR-INVALID-INPUT)

    (ok (map-set authorized-technicians
      { technician-id: technician-id }
      {
        name: name,
        certification-level: certification-level,
        certification-expiry: certification-expiry,
        active: true
      }
    ))
  )
)

;; Register equipment calibration
(define-public (register-equipment
  (equipment-id (string-ascii 30))
  (serial-number (string-ascii 50))
  (manufacturer (string-ascii 50))
  (model (string-ascii 50))
  (calibration-date uint)
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (calibration-due (+ calibration-date (var-get calibration-interval)))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len equipment-id) u0) ERR-INVALID-INPUT)
    (asserts! (< calibration-date current-time) ERR-INVALID-INPUT)

    (ok (map-set equipment-calibration
      { equipment-id: equipment-id }
      {
        last-calibration: calibration-date,
        calibration-due: calibration-due,
        accuracy-rating: u95,
        serial-number: serial-number,
        manufacturer: manufacturer,
        model: model,
        status: "active"
      }
    ))
  )
)

;; Record flow test results
(define-public (record-flow-test
  (hydrant-id (string-ascii 20))
  (technician-id (string-ascii 30))
  (static-pressure uint)
  (residual-pressure uint)
  (flow-rate-gpm uint)
  (test-duration uint)
  (weather-conditions (string-ascii 50))
  (equipment-used (string-ascii 100))
)
  (let
    (
      (test-id (var-get next-test-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-authorized-technician technician-id) ERR-NOT-AUTHORIZED)
    (asserts! (> (len hydrant-id) u0) ERR-INVALID-INPUT)
    (asserts! (> static-pressure u0) ERR-INVALID-MEASUREMENT)
    (asserts! (> flow-rate-gpm u0) ERR-INVALID-MEASUREMENT)
    (asserts! (< residual-pressure static-pressure) ERR-INVALID-MEASUREMENT)
    (asserts! (> test-duration u0) ERR-INVALID-INPUT)

    (map-set flow-test-results
      { test-id: test-id }
      {
        hydrant-id: hydrant-id,
        test-date: current-time,
        technician-id: technician-id,
        static-pressure: static-pressure,
        residual-pressure: residual-pressure,
        flow-rate-gpm: flow-rate-gpm,
        test-duration: test-duration,
        weather-conditions: weather-conditions,
        equipment-used: equipment-used,
        test-status: "completed",
        created-at: current-time
      }
    )

    (var-set next-test-id (+ test-id u1))
    (ok test-id)
  )
)

;; Record detailed measurements
(define-public (record-measurement-details
  (test-id uint)
  (outlet-count uint)
  (outlet-sizes (string-ascii 50))
  (pressure-readings (list 10 uint))
  (flow-readings (list 10 uint))
  (temperature uint)
  (notes (string-ascii 200))
)
  (let
    (
      (test-result (unwrap! (map-get? flow-test-results { test-id: test-id }) ERR-TEST-NOT-FOUND))
    )
    (asserts! (is-authorized-technician (get technician-id test-result)) ERR-NOT-AUTHORIZED)
    (asserts! (> outlet-count u0) ERR-INVALID-INPUT)
    (asserts! (> (len pressure-readings) u0) ERR-INVALID-INPUT)
    (asserts! (> (len flow-readings) u0) ERR-INVALID-INPUT)

    (ok (map-set measurement-details
      { test-id: test-id }
      {
        outlet-count: outlet-count,
        outlet-sizes: outlet-sizes,
        pressure-readings: pressure-readings,
        flow-readings: flow-readings,
        temperature: temperature,
        ph-level: u7,
        turbidity: u1,
        chlorine-level: u2,
        notes: notes
      }
    ))
  )
)

;; Update test status
(define-public (update-test-status
  (test-id uint)
  (new-status (string-ascii 20))
)
  (let
    (
      (test-result (unwrap! (map-get? flow-test-results { test-id: test-id }) ERR-TEST-NOT-FOUND))
    )
    (asserts! (is-authorized-technician (get technician-id test-result)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)

    (ok (map-set flow-test-results
      { test-id: test-id }
      (merge test-result { test-status: new-status })
    ))
  )
)

;; Read-only Functions

;; Get flow test results
(define-read-only (get-flow-test-results (test-id uint))
  (map-get? flow-test-results { test-id: test-id })
)

;; Get measurement details
(define-read-only (get-measurement-details (test-id uint))
  (map-get? measurement-details { test-id: test-id })
)

;; Get equipment calibration status
(define-read-only (get-equipment-status (equipment-id (string-ascii 30)))
  (map-get? equipment-calibration { equipment-id: equipment-id })
)

;; Check technician authorization
(define-read-only (check-technician-auth (technician-id (string-ascii 30)))
  (is-authorized-technician technician-id)
)

;; Get technician info
(define-read-only (get-technician-info (technician-id (string-ascii 30)))
  (map-get? authorized-technicians { technician-id: technician-id })
)

;; Validate flow rate measurement
(define-read-only (validate-flow-measurement
  (static-pressure uint)
  (residual-pressure uint)
  (flow-rate uint)
)
  (and
    (> static-pressure u0)
    (> flow-rate u0)
    (< residual-pressure static-pressure)
    (> static-pressure u20) ;; Minimum 20 PSI
    (< flow-rate u3000) ;; Maximum reasonable flow rate
  )
)
