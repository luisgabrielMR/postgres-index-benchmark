-- Load deterministic fake data for a controlled local benchmark.
TRUNCATE TABLE orders RESTART IDENTITY;

INSERT INTO orders (
    customer_id,
    status,
    total_amount,
    created_at,
    description
)
SELECT
    ((gs - 1) % 10000) + 1 AS customer_id,
    CASE
        WHEN gs % 10 IN (0, 1, 2, 3, 4, 5) THEN 'PAID'
        WHEN gs % 10 IN (6, 7) THEN 'PENDING'
        WHEN gs % 10 = 8 THEN 'CANCELED'
        ELSE 'REFUNDED'
    END AS status,
    (10 + ((gs * 17) % 90000) / 100.0)::NUMERIC(10,2) AS total_amount,
    TIMESTAMP '2024-01-01 00:00:00'
        + ((gs % 365) * INTERVAL '1 day')
        + ((gs % 86400) * INTERVAL '1 second') AS created_at,
    'Generated order #' || gs AS description
FROM generate_series(1, 499000) AS series(gs);

-- Target rows ensure the benchmark query always returns data.
INSERT INTO orders (
    customer_id,
    status,
    total_amount,
    created_at,
    description
)
SELECT
    12345 AS customer_id,
    'PAID' AS status,
    (50 + ((gs * 13) % 10000) / 100.0)::NUMERIC(10,2) AS total_amount,
    TIMESTAMP '2025-01-01 00:00:00' + (gs * INTERVAL '5 minutes') AS created_at,
    'Benchmark target order #' || gs AS description
FROM generate_series(1, 1000) AS series(gs);

ANALYZE orders;
