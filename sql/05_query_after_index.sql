-- Same query as 03_query_before_index.sql, now after creating the composite index.
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
