#!/bin/bash
# Common test helper functions

TEST_COUNT=0
TEST_FAILED=0

start_test() {
    local name="$1"
    TEST_COUNT=$((TEST_COUNT + 1))
    echo "TEST $TEST_COUNT: $name"
}

pass_test() {
    local name="$1"
    echo "PASS $TEST_COUNT: $name"
}

fail_test() {
    local name="$1"
    echo "FAIL $TEST_COUNT: $name" >&2
    TEST_FAILED=$((TEST_FAILED + 1))
}

end_test_summary() {
    echo "DONE: PASS=$((TEST_COUNT - TEST_FAILED)) FAIL=$TEST_FAILED"
    [ $TEST_FAILED -eq 0 ] || exit 1
}

test_error() {
    echo "$*"
    exit 1
}

# Setup a unique .volund dir for a test. Uses .volund_test_XXXXXX template.
# Sets VOLUND_VAR_DIR and VOLUND_TMP_DIR.
setup_test_volund() {
    local template="${1:-.volund_test}"
    VOLUND_VAR_DIR=$(mktemp -d "${template}_XXXXXX")
    VOLUND_TMP_DIR="$VOLUND_VAR_DIR/tmp"
    mkdir -p "$VOLUND_TMP_DIR"
}

# Cleanup the test volund dir. If failed!=0, leave it for debugging.
cleanup_test_volund() {
    local failed="${1:-0}"
    if [ -n "${VOLUND_VAR_DIR:-}" ] && [ -d "$VOLUND_VAR_DIR" ]; then
        if [ "$failed" -eq 0 ]; then
            rm -rf "$VOLUND_VAR_DIR"
        else
            echo "Leaving for debugging: $VOLUND_VAR_DIR"
        fi
    fi
}

# vi: filetype=sh expandtab sw=4
