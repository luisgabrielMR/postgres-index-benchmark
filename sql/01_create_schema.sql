-- Recreate the benchmark table so the experiment starts from a known state.
DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    status VARCHAR(20) NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    description TEXT
);
