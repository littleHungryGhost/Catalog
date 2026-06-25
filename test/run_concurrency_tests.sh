#!/bin/bash
# run_concurrency_tests.sh — Run multi-session SQL tests for iceberg_catalog.
#
# Each concurrency test consists of:
#   <name>_setup.sql    - optional sequential setup (runs against 'postgres')
#   <name>_session*.sql - concurrent sessions (run against ICEBERG_CONCUR_DB)
#   <name>_verify.sql   - optional sequential invariant checks
#   <name>.pattern      - expected output patterns for the concurrent sessions
#
# Usage:
#   bash test/run_concurrency_tests.sh              # run all tests
#   bash test/run_concurrency_tests.sh -g           # regenerate pattern baselines
#   bash test/run_concurrency_tests.sh <test_name>  # run/generate single test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="$SCRIPT_DIR/concurrent/sql"
EXPECTED_DIR="$SCRIPT_DIR/concurrent/expected"
RESULTS_DIR="$SCRIPT_DIR/concurrent/results"
PORT="${TEST_PORT:-37555}"
DB="${ICEBERG_CONCUR_DB:-iceberg_concur_test}"
TEST_TIMEOUT="${TEST_TIMEOUT:-30}"
GEN=false
FILTER=""

for arg in "$@"; do
    case "$arg" in
        -g) GEN=true ;;
        *)  FILTER="$arg" ;;
    esac
done

mkdir -p "$RESULTS_DIR" "$EXPECTED_DIR"

normalize() {
    sed -E '
        /^total time: /d
        /^[[:space:]]*$/d
        s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/g
        s/"last-updated-ms": [0-9]+/"last-updated-ms": <ts>/g
        s/iceberg_concur_test/<test_db>/g
        s#gsql:[^ ]+test/concurrent/sql/#gsql:test/concurrent/sql/#g
    '
}

# ---------------------------------------------------------------------------
# Run the optional setup SQL file against the 'postgres' database.
# The setup is responsible for dropping/creating $DB and creating extensions.
# ---------------------------------------------------------------------------
run_setup() {
    local name="$1"
    local setup_file="$SQL_DIR/${name}_setup.sql"

    if [[ ! -f "$setup_file" ]]; then
        return 0
    fi

    local out_file="$RESULTS_DIR/${name}_setup.out"
    if gsql -a -d postgres -p "$PORT" -f "$setup_file" > "$out_file" 2>&1; then
        return 0
    else
        echo "  ✗ SETUP FAILED (exit $?)"
        tail -30 "$out_file"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Run the optional verify SQL file against the concurrency database.
# Every non-empty line must be 't' (true).
# ---------------------------------------------------------------------------
run_verify() {
    local name="$1"
    local verify_file="$SQL_DIR/${name}_verify.sql"

    if [[ ! -f "$verify_file" ]]; then
        return 0
    fi

    local out_file="$RESULTS_DIR/${name}_verify.out"
    gsql -At -d "$DB" -p "$PORT" -f "$verify_file" > "$out_file" 2>&1

    local bad
    bad="$(grep -v '^t$' "$out_file" | grep -v '^$' | grep -v '^total time: ' || true)"
    if [[ -n "$bad" ]]; then
        echo "  ✗ VERIFY FAILED"
        echo "$bad"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Match the combined concurrent session output against a pattern file.
#   + <regex>  - must appear at least once
#   ! <regex>  - must not appear
#   - <regex>  - alias for !
#   # comment  - ignored
# ---------------------------------------------------------------------------
match_pattern() {
    local combined="$1"
    local pattern="$2"
    local fail=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # strip trailing carriage returns
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^# ]] && continue

        local op="${line:0:1}"
        local regex="${line:2}"

        case "$op" in
            +)
                if ! grep -qE -- "$regex" "$combined"; then
                    echo "  pattern not found: $regex"
                    fail=1
                fi
                ;;
            !|-)
                if grep -qE -- "$regex" "$combined"; then
                    echo "  forbidden pattern found: $regex"
                    fail=1
                fi
                ;;
            *)
                echo "  unknown pattern operator '$op' in: $line"
                fail=1
                ;;
        esac
    done < "$pattern"

    return "$fail"
}

# ---------------------------------------------------------------------------
# Run one concurrency test.
# ---------------------------------------------------------------------------
run_test() {
    local name="$1"
    local pattern_file="$EXPECTED_DIR/${name}.pattern"
    local combined_file="$RESULTS_DIR/${name}_combined.out"

    echo ""
    echo "──── $name ────"

    if [[ ! -f "$pattern_file" ]]; then
        echo "  → No pattern file: $pattern_file"
        return 1
    fi

    local sessions=()
    for f in "$SQL_DIR/${name}_session"*.sql; do
        [[ -f "$f" ]] && sessions+=("$f")
    done

    if [[ ${#sessions[@]} -eq 0 ]]; then
        echo "  → No session files for '$name'"
        return 1
    fi

    # Setup
    if ! run_setup "$name"; then
        return 1
    fi

    # Barrier + concurrent sessions
    local barrier_dir
    barrier_dir="$(mktemp -d)"
    local pids=()

    for session in "${sessions[@]}"; do
        (
            local base
            base="$(basename "$session" .sql)"
            touch "$barrier_dir/ready_$base"
            while [[ ! -f "$barrier_dir/GO" ]]; do
                sleep 0.05
            done

            local out_file="$RESULTS_DIR/${base}.out"
            if timeout "$TEST_TIMEOUT" gsql -a -d "$DB" -p "$PORT" -f "$session" > "$out_file" 2>&1; then
                echo 0 > "$barrier_dir/exit_$base"
            else
                echo "$?" > "$barrier_dir/exit_$base"
            fi
        ) &
        pids+=("$!")
    done

    # Wait until every session reports ready, then signal GO.
    while [[ $(ls -1 "$barrier_dir"/ready_* 2>/dev/null | wc -l) -lt ${#sessions[@]} ]]; do
        sleep 0.05
    done
    touch "$barrier_dir/GO"

    # Wait for all sessions to finish (timeout already enforced inside each).
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    # Combine and normalize session outputs.
    cat "$RESULTS_DIR/${name}_session"*.out | normalize > "$combined_file"

    rm -rf "$barrier_dir"

    if $GEN; then
        echo "----- $name combined output -----"
        cat "$combined_file"
        echo "---------------------------------"
        read -r -p "Accept as baseline pattern? [Y/n] " reply
        case "$reply" in
            n|N|no|NO) echo "  → SKIPPED"; return 0 ;;
            *) cp "$combined_file" "$pattern_file"; echo "  → BASELINE SAVED"; return 0 ;;
        esac
    fi

    # Pattern matching.
    if ! match_pattern "$combined_file" "$pattern_file"; then
        echo "  ✗ PATTERN FAIL"
        return 1
    fi

    # Verify invariants.
    if ! run_verify "$name"; then
        return 1
    fi

    echo "  ✓ PASS"
    return 0
}

# ---------------------------------------------------------------------------
# Collect tests to run.
# ---------------------------------------------------------------------------
tests=()
if [[ -n "$FILTER" ]]; then
    base="${FILTER%.pattern}"
    base="${base%.sql}"
    if [[ ! -f "$EXPECTED_DIR/${base}.pattern" ]]; then
        echo "ERROR: concurrency test '$FILTER' not found in $EXPECTED_DIR/"
        echo "Available tests:"
        for f in "$EXPECTED_DIR"/*.pattern; do
            [[ -f "$f" ]] && echo "  $(basename "$f" .pattern)"
        done
        exit 1
    fi
    tests+=("$base")
else
    for f in "$EXPECTED_DIR"/*.pattern; do
        [[ -f "$f" ]] && tests+=("$(basename "$f" .pattern)")
    done
fi

if [[ ${#tests[@]} -eq 0 ]]; then
    echo "No concurrency tests found in $EXPECTED_DIR/"
    exit 0
fi

# ---------------------------------------------------------------------------
# Main loop.
# ---------------------------------------------------------------------------
pass=0
fail=0

for name in "${tests[@]}"; do
    if run_test "$name"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
    fi
done

echo ""
echo "═══════════════════════════════════════"
if $GEN; then
    echo " Concurrency baseline generation complete."
else
    echo " ${pass} passed, ${fail} failed"
fi
echo "═══════════════════════════════════════"

exit "$fail"
