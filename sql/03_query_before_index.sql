-- Scenario before the specific index for this query.
-- PostgreSQL may need to inspect many rows before returning the 20 most recent matches.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    id,
    customer_id,
    status,
    total_amount,
    created_at
FROM orders
WHERE customer_id = 12345
  AND status = 'PAID'
ORDER BY created_at DESC
LIMIT 20;
