-- Composite index aligned with the filter columns and the ORDER BY direction.
CREATE INDEX idx_orders_customer_status_created_at
ON orders (customer_id, status, created_at DESC);

ANALYZE orders;
