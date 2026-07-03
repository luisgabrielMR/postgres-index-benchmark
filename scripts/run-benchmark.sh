#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/results"

cd "$PROJECT_ROOT"
mkdir -p "$RESULTS_DIR"

echo "Starting PostgreSQL with Docker Compose..."
docker compose up -d

echo "Waiting for PostgreSQL to become available..."
for attempt in {1..60}; do
    if docker compose exec -T postgres pg_isready -U postgres -d index_benchmark > /dev/null 2>&1; then
        echo "PostgreSQL is ready."
        break
    fi

    if [ "$attempt" -eq 60 ]; then
        echo "PostgreSQL did not become available in time." >&2
        exit 1
    fi

    sleep 1
done

run_sql() {
    local script_path="$1"
    docker compose exec -T postgres psql \
        -U postgres \
        -d index_benchmark \
        -v ON_ERROR_STOP=1 \
        -f "$script_path"
}

echo "Creating schema..."
run_sql /sql/01_create_schema.sql

echo "Seeding fake data..."
run_sql /sql/02_seed_data.sql

echo "Running query before index..."
docker compose exec -T postgres psql \
    -U postgres \
    -d index_benchmark \
    -v ON_ERROR_STOP=1 \
    -f /sql/03_query_before_index.sql > "$RESULTS_DIR/before-index.txt"

echo "Creating index..."
run_sql /sql/04_create_index.sql

echo "Running query after index..."
docker compose exec -T postgres psql \
    -U postgres \
    -d index_benchmark \
    -v ON_ERROR_STOP=1 \
    -f /sql/05_query_after_index.sql > "$RESULTS_DIR/after-index.txt"

extract_execution_time() {
    local file_path="$1"
    grep -E "Execution Time: [0-9.]+ ms" "$file_path" \
        | tail -n 1 \
        | sed -E "s/.*Execution Time: ([0-9.]+) ms.*/\1/" || true
}

extract_top_level_shared_buffer_metric() {
    local file_path="$1"
    local metric_name="$2"
    local line

    line="$(grep -m 1 "Buffers: shared" "$file_path" || true)"
    if [[ "$line" =~ $metric_name=([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0"
    fi
}

extract_first_metric() {
    local file_path="$1"
    local pattern="$2"
    local replacement="$3"
    local line

    line="$(grep -m 1 -E "$pattern" "$file_path" || true)"
    if [ -z "$line" ]; then
        echo "0"
        return
    fi

    echo "$line" | sed -E "$replacement"
}

before_ms="$(extract_execution_time "$RESULTS_DIR/before-index.txt")"
after_ms="$(extract_execution_time "$RESULTS_DIR/after-index.txt")"

{
    echo "scenario,execution_time_ms"
    echo "before_index,$before_ms"
    echo "after_index,$after_ms"
} > "$RESULTS_DIR/summary.csv"

before_shared_hits="$(extract_top_level_shared_buffer_metric "$RESULTS_DIR/before-index.txt" "hit")"
before_shared_reads="$(extract_top_level_shared_buffer_metric "$RESULTS_DIR/before-index.txt" "read")"
before_rows_removed="$(extract_first_metric "$RESULTS_DIR/before-index.txt" "Rows Removed by Filter: [0-9]+" "s/.*Rows Removed by Filter: ([0-9]+).*/\1/")"
before_sort_memory_kb="$(extract_first_metric "$RESULTS_DIR/before-index.txt" "Sort Method: .* Memory: [0-9]+kB" "s/.*Memory: ([0-9]+)kB.*/\1/")"
before_workers_launched="$(extract_first_metric "$RESULTS_DIR/before-index.txt" "Workers Launched: [0-9]+" "s/.*Workers Launched: ([0-9]+).*/\1/")"

after_shared_hits="$(extract_top_level_shared_buffer_metric "$RESULTS_DIR/after-index.txt" "hit")"
after_shared_reads="$(extract_top_level_shared_buffer_metric "$RESULTS_DIR/after-index.txt" "read")"
after_rows_removed="$(extract_first_metric "$RESULTS_DIR/after-index.txt" "Rows Removed by Filter: [0-9]+" "s/.*Rows Removed by Filter: ([0-9]+).*/\1/")"
after_sort_memory_kb="$(extract_first_metric "$RESULTS_DIR/after-index.txt" "Sort Method: .* Memory: [0-9]+kB" "s/.*Memory: ([0-9]+)kB.*/\1/")"
after_workers_launched="$(extract_first_metric "$RESULTS_DIR/after-index.txt" "Workers Launched: [0-9]+" "s/.*Workers Launched: ([0-9]+).*/\1/")"

{
    echo "scenario,shared_hit_blocks,shared_read_blocks,rows_removed_by_filter,sort_memory_kb,workers_launched"
    echo "before_index,$before_shared_hits,$before_shared_reads,$before_rows_removed,$before_sort_memory_kb,$before_workers_launched"
    echo "after_index,$after_shared_hits,$after_shared_reads,$after_rows_removed,$after_sort_memory_kb,$after_workers_launched"
} > "$RESULTS_DIR/resource-summary.csv"

echo "Benchmark finished."
echo "Results saved to:"
echo "- $RESULTS_DIR/before-index.txt"
echo "- $RESULTS_DIR/after-index.txt"
echo "- $RESULTS_DIR/summary.csv"
echo "- $RESULTS_DIR/resource-summary.csv"
