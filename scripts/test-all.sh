#!/usr/bin/env bash
set -euo pipefail

# test-all.sh — comprehensive workspace test runner for solid-pod-rs.
#
# Runs cargo test --workspace, shows per-crate pass/fail, counts tests,
# prints a coverage density report (tests/KLOC). Exit 0 only if all pass.

WORKSPACE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE_ROOT"

# ---------------------------------------------------------------------------
# Colours (disable if not a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' RED='' YELLOW='' BOLD='' RESET=''
fi

# ---------------------------------------------------------------------------
# Discover workspace crates from Cargo.toml
# ---------------------------------------------------------------------------
CRATES=(
    "solid-pod-rs"
    "solid-pod-rs-server"
    "solid-pod-rs-activitypub"
    "solid-pod-rs-git"
    "solid-pod-rs-idp"
    "solid-pod-rs-nostr"
    "solid-pod-rs-didkey"
)

echo -e "${BOLD}solid-pod-rs Workspace Test Runner${RESET}"
echo "===================================="
echo ""

# ---------------------------------------------------------------------------
# Count tests per crate (best-effort, does not require compilation)
# ---------------------------------------------------------------------------
count_tests_in_crate() {
    local crate_dir="$1"
    local count=0

    # Count #[test] and #[tokio::test] in src/ and tests/
    if [[ -d "$crate_dir/src" ]]; then
        count=$((count + $(grep -rE '#\[(tokio::)?test\]' "$crate_dir/src" 2>/dev/null | wc -l)))
    fi
    if [[ -d "$crate_dir/tests" ]]; then
        count=$((count + $(grep -rE '#\[(tokio::)?test\]' "$crate_dir/tests" 2>/dev/null | wc -l)))
    fi
    echo "$count"
}

count_loc_in_crate() {
    local crate_dir="$1"
    local loc=0
    if [[ -d "$crate_dir/src" ]]; then
        loc=$(find "$crate_dir/src" -name '*.rs' -exec cat {} + 2>/dev/null | wc -l)
    fi
    echo "$loc"
}

# ---------------------------------------------------------------------------
# Per-crate summary table (pre-run)
# ---------------------------------------------------------------------------
total_tests=0
total_loc=0

declare -A crate_tests
declare -A crate_loc

echo -e "${BOLD}Test Census (grep-based, pre-run):${RESET}"
printf "%-35s %8s %8s %12s\n" "Crate" "Tests" "LOC" "Tests/KLOC"
printf "%-35s %8s %8s %12s\n" "-----------------------------------" "--------" "--------" "------------"

for crate in "${CRATES[@]}"; do
    crate_dir="$WORKSPACE_ROOT/crates/$crate"
    if [[ ! -d "$crate_dir" ]]; then
        continue
    fi

    tests=$(count_tests_in_crate "$crate_dir")
    loc=$(count_loc_in_crate "$crate_dir")
    crate_tests[$crate]=$tests
    crate_loc[$crate]=$loc
    total_tests=$((total_tests + tests))
    total_loc=$((total_loc + loc))

    if [[ $loc -gt 0 ]]; then
        density=$(awk "BEGIN { printf \"%.1f\", ($tests / ($loc / 1000.0)) }")
    else
        density="N/A"
    fi
    printf "%-35s %8d %8d %12s\n" "$crate" "$tests" "$loc" "$density"
done

echo ""
if [[ $total_loc -gt 0 ]]; then
    total_density=$(awk "BEGIN { printf \"%.1f\", ($total_tests / ($total_loc / 1000.0)) }")
else
    total_density="N/A"
fi
printf "%-35s %8d %8d %12s\n" "TOTAL" "$total_tests" "$total_loc" "$total_density"
echo ""

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------
echo -e "${BOLD}Running cargo test --workspace --all-features ...${RESET}"
echo ""

CARGO_ARGS=(test --workspace --all-features)

# Try online first; fall back to --offline on network error.
TEST_LOG=$(mktemp)
EXIT_CODE=0

if cargo "${CARGO_ARGS[@]}" 2>&1 | tee "$TEST_LOG"; then
    EXIT_CODE=0
else
    EXIT_CODE=${PIPESTATUS[0]}
    # Check if the failure is a network issue — retry offline.
    if grep -qiE '(network|download|registry|fetching|Unable to update)' "$TEST_LOG" 2>/dev/null; then
        echo ""
        echo -e "${YELLOW}Network error detected. Retrying with --offline ...${RESET}"
        echo ""
        if cargo "${CARGO_ARGS[@]}" --offline 2>&1 | tee "$TEST_LOG"; then
            EXIT_CODE=0
        else
            EXIT_CODE=${PIPESTATUS[0]}
        fi
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Parse results per crate
# ---------------------------------------------------------------------------
echo -e "${BOLD}Per-Crate Results:${RESET}"
printf "%-35s %10s\n" "Crate" "Status"
printf "%-35s %10s\n" "-----------------------------------" "----------"

all_pass=true
for crate in "${CRATES[@]}"; do
    # Look for the "test result:" line emitted by cargo test for this crate.
    # cargo test output includes "running N tests" and "test result: ok/FAILED".
    if grep -q "test result: FAILED" "$TEST_LOG" 2>/dev/null && grep -B 50 "test result: FAILED" "$TEST_LOG" | grep -q "$crate" 2>/dev/null; then
        printf "%-35s ${RED}%10s${RESET}\n" "$crate" "FAIL"
        all_pass=false
    elif grep -q "$crate" "$TEST_LOG" 2>/dev/null; then
        printf "%-35s ${GREEN}%10s${RESET}\n" "$crate" "PASS"
    else
        printf "%-35s ${YELLOW}%10s${RESET}\n" "$crate" "SKIPPED"
    fi
done

echo ""

# ---------------------------------------------------------------------------
# Coverage density report
# ---------------------------------------------------------------------------
echo -e "${BOLD}Coverage Density Report (tests/KLOC):${RESET}"
echo ""
printf "  Total tests discovered : %d\n" "$total_tests"
printf "  Total source LOC       : %d\n" "$total_loc"
printf "  Workspace density      : %s tests/KLOC\n" "$total_density"
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}ALL TESTS PASSED${RESET}"
else
    echo -e "${RED}${BOLD}SOME TESTS FAILED (exit code $EXIT_CODE)${RESET}"
fi

rm -f "$TEST_LOG"
exit "$EXIT_CODE"
