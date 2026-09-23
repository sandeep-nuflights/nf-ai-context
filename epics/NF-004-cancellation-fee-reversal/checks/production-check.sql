-- NF-004 production check — the epic's declared first action.
-- READ ONLY. No writes, no locks beyond a shared read.
-- Column names verified against models.py on 2026-09-23.
--
-- Purpose: decide whether NF-004 is migrating a working feature or
-- implementing an intended one. Three branches of the design depend on it.

\echo '=== 1. Is the legacy fee/commission engine configured at all? ==='
-- Empty => process_fee_commission_ledger() returns at its first guard
-- (ledger_service.py:33-34) on every call, and no reversal has ever run.
SELECT count(*)                                            AS configs,
       count(*) FILTER (WHERE service_fee_enabled)         AS fee_enabled,
       count(*) FILTER (WHERE commission_enabled)          AS commission_enabled,
       count(*) FILTER (WHERE coalesce(service_fee_formula, '') <> '') AS with_fee_formula,
       count(*) FILTER (WHERE coalesce(commission_formula, '') <> '')  AS with_comm_formula
FROM content_orgrelationshipconfig;

\echo '=== 2. Has a fee or commission ever posted to the accounting ledger? ==='
-- FEE / COMMISSION rows are what a reversal offsets. Zero => nothing to reverse,
-- ever, and D10 charged is definitionally false everywhere.
SELECT entry_type, count(*) AS entries, min(created_at) AS first_seen, max(created_at) AS last_seen
FROM content_ledgerentry
GROUP BY entry_type
ORDER BY entries DESC;

\echo '=== 3. How large is the legacy cohort? (sizes D10 fallback) ==='
-- Rows carrying the write-once formula snapshot = charges made by the config
-- engine. This count IS the legacy cohort. Zero => D10 fallback arm is dead
-- code and is not built.
-- NOTE: IS NOT NULL, not truthiness — '' is a real stored value meaning
-- "legacy ran, fee disabled" (ledger_service.py:62-63).
SELECT count(*)                                                        AS ticket_org_rows,
       count(*) FILTER (WHERE applied_service_fee_formula IS NOT NULL) AS fee_snapshot,
       count(*) FILTER (WHERE applied_commission_formula IS NOT NULL)  AS comm_snapshot,
       count(*) FILTER (WHERE applied_service_fee_formula IS NOT NULL
                           OR applied_commission_formula IS NOT NULL)  AS legacy_cohort
FROM content_ticketorgtransactions;

\echo '=== 4. Is the legacy cohort still cancellable? (sizes the fallback tail) ==='
-- Only rows whose ticket is still live matter — a fully flown or already
-- cancelled document will never reverse. Bounds how long the fallback lives.
SELECT tt.txn_coupon_status, count(*) AS rows
FROM content_ticketorgtransactions tot
JOIN content_tickettransactions tt ON tt.id = tot.ticket_transaction_id
WHERE tot.applied_service_fee_formula IS NOT NULL
   OR tot.applied_commission_formula IS NOT NULL
GROUP BY tt.txn_coupon_status
ORDER BY rows DESC;

\echo '=== 5. Does any reversal actually exist to build fixtures from? ==='
-- A FEE/COMMISSION entry against a Void/Refunded charge is an observed
-- reversal. Non-zero => fixtures can be captured. Zero => they can only be
-- agreed, and the parity gate changes meaning.
SELECT tt.txn_coupon_status, le.entry_type, count(*) AS entries
FROM content_ledgerentry le
JOIN django_content_type ct ON ct.id = le.content_type_id
                           AND ct.app_label = 'content'
                           AND ct.model = 'ticketorgtransactions'
JOIN content_ticketorgtransactions tot ON tot.id::text = le.object_id
JOIN content_tickettransactions tt ON tt.id = tot.ticket_transaction_id
WHERE le.entry_type IN ('FEE', 'COMMISSION')
  AND tt.txn_coupon_status IN ('Void', 'Refunded')
GROUP BY tt.txn_coupon_status, le.entry_type
ORDER BY entries DESC;
