#!/bin/bash
#
# Tests for volund/lib/core
#

set -eo pipefail
set +u

cd "$(dirname "$0")/.."

. lib/core
. tests/_helper.sh

TEST_IMAGE='mirror.gcr.io/library/alpine:3.24.1'

# --- Tests ---

test_var_prefix_and_naming() {
    local TEST_NAME="var prefix and naming"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        v_foo="bar"
        volund_save_var v_foo
        [ -f "$VOLUND_VAR_DIR/var.v_foo" ] || { echo "file not created"; exit 1; }
        [ "$(cat "$VOLUND_VAR_DIR/var.v_foo")" = "$v_foo" ] || { echo "wrong value"; exit 1; }

        # must not be exported
        env | grep -q "^v_foo=" && { echo "should not be exported"; exit 1; } || true

        set +e
        # bad name (uppercase) must error
        out=$( ( volund_save_var v_Bad ) 2>&1 )
        echo "$out" | grep -q "lowercase" || { echo "bad name did not error: $out"; exit 1; }

        # bad prefix
        out=$( ( volund_var_prefix "vv_"; volund_save_var v_foo ) 2>&1 )
        echo "$out" | grep -q "prefix" || { echo "prefix check failed: $out"; exit 1; }
        set -e
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_load_save_no_export() {
    local TEST_NAME="load save no export"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        v_test="hello world"
        volund_save_var v_test

        # fresh load in same shell after unset
        unset v_test
        volund_load_vars
        [ "${v_test:-}" = "hello world" ] || { echo "load failed"; exit 1; }

        # still not exported
        env | grep -q "^v_test=" && { echo "exported after load"; exit 1; } || true
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_cmd_real() {
    local TEST_NAME="volund_cmd"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        volund_image sh "$TEST_IMAGE"

        out=$(volund_cmd sh cat /etc/os-release | grep '^VERSION_ID=3.24.1')
        [ "$out" = "VERSION_ID=3.24.1" ] || { echo "wrong cmd output: $out"; exit 1; }
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_script_real() {
    local TEST_NAME="volund_script"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    export VOLUND_VAR_DIR
    volund_env VOLUND_VAR_DIR
    (
        volund_clean
        volund_image sh "$TEST_IMAGE"

        volund_script sh << "EOF"
echo "script begin"
cat /etc/os-release | sed -rn 's/^VERSION_ID=([0-9.-]+)/\1/p' | \
tee "${VOLUND_VAR_DIR}/var.v_os_release"
echo "script end"
EOF

        volund_load_vars
        [ "${v_os_release:-}" = "3.24.1" ] || { echo "wrong persisted var content: '$v_os_release'"; exit 1; }

        # shellcheck disable=SC2034
        FORCE_COLOR=0
        # shellcheck disable=SC2034
        NO_COLOR=1
        err=$(volund_script sh "custom script label" << "EOF" 2>&1 >/dev/null
echo ignored
EOF
)
        echo "$err" | grep -q "script sh custom script label" || {
            echo "missing custom script label: $err"
            exit 1
        }
        if echo "$err" | grep -q "echo ignored"; then
            echo "first line leaked despite label: $err"
            exit 1
        fi
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_prefix_change_and_validation_on_load() {
    local TEST_NAME="prefix change and validation on load"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        # Note: we intentionally pass a name that will fail prefix validation after the change.
        # No need to assign a value since validation happens before reading ${!name}.
        volund_save_var v_ok

        # change prefix and load should fail on existing file
        volund_var_prefix "x_"
        set +e
        out=$( volund_load_vars 2>&1 )
        echo "$out" | grep -q "prefix" || { echo "load validation on prefix failed: $out"; exit 1; }
        set -e
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_volund_with() {
    local TEST_NAME="volund_with extras"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        volund_image sh "$TEST_IMAGE"

        out_file="$VOLUND_TMP_DIR/marker.out"
        volund_with -e VOLUND_TEST_MARKER=from-with -- \
            volund_cmd sh printenv VOLUND_TEST_MARKER >"$out_file"
        out=$(cat "$out_file")
        [ "$out" = "from-with" ] || { echo "wrong marker: $out"; exit 1; }

        set +e
        volund_cmd sh printenv VOLUND_TEST_MARKER >"$out_file" 2>/dev/null
        rc2=$?
        set -e
        out2=$(cat "$out_file" 2>/dev/null || true)
        [ "$rc2" -ne 0 ] || [ -z "$out2" ] || {
            echo "marker leaked into next call: $out2"
            exit 1
        }
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_volund_with_spaces() {
    local TEST_NAME="volund_with preserves spaces"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        volund_image sh "$TEST_IMAGE"

        out_file="$VOLUND_TMP_DIR/msg.out"
        volund_with -e "VOLUND_TEST_MSG=hello world" -- \
            volund_cmd sh printenv VOLUND_TEST_MSG >"$out_file"
        out=$(cat "$out_file")
        [ "$out" = "hello world" ] || { echo "spaces broken: '$out'"; exit 1; }
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_volund_log_and_help() {
    local TEST_NAME="volund_log and help"
    start_test "$TEST_NAME"
    local failed=0
    (
        VOLUND_LOG_LEVEL=info
        err=$(volund_log info "hello-log-line" 2>&1)
        echo "$err" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z INFO hello-log-line$' || {
            echo "bad info format: $err"
            exit 1
        }

        VOLUND_LOG_LEVEL=error
        err=$(volund_log info "should-be-hidden" 2>&1)
        [ -z "$err" ] || { echo "info leaked at error level: $err"; exit 1; }

        VOLUND_LOG_LEVEL=info
        # shellcheck disable=SC2034  # read by volund_log / volund_color
        FORCE_COLOR=1
        unset NO_COLOR
        err=$(volund_log info "hello-color" 2>&1)
        echo "$err" | grep -q $'\033' || { echo "FORCE_COLOR should emit ANSI: $err"; exit 1; }
        echo "$err" | grep -qE 'hello-color$' || {
            echo "log message should be after reset, at end of line: $err"
            exit 1
        }

        VOLUND_DEFAULTS="clean"
        out=$(volund_main --help)
        echo "$out" | grep -q 'Usage:' || { echo "help missing Usage: $out"; exit 1; }
        echo "$out" | grep -q 'Default targets: clean' || { echo "help missing defaults: $out"; exit 1; }
    ) || failed=1
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_volund_api_logs() {
    local TEST_NAME="volund_main/image/env/save_var logs"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        # Invoked by name via volund_main (not a direct call).
        # shellcheck disable=SC2329
        dummy_target() { :; }
        VOLUND_LOG_LEVEL=info
        err=$(volund_main dummy_target 2>&1)
        echo "$err" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z INFO ====> dummy_target$' || {
            echo "missing target start log: $err"
            exit 1
        }

        # Keep registration in this shell; $() would drop VOLUND_IMAGES.
        volund_image myalias example.com/img:1 2>"$VOLUND_TMP_DIR/image.log"
        err=$(cat "$VOLUND_TMP_DIR/image.log")
        echo "$err" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z INFO image myalias example.com/img:1$' || {
            echo "missing image log: $err"
            exit 1
        }

        VOLUND_LOG_LEVEL=info
        set +e
        err=$( ( volund_cmd nosuch true ) 2>&1 )
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || { echo "unknown alias should fail"; exit 1; }
        echo "$err" | grep -q "unknown image alias 'nosuch'" || {
            echo "missing unknown alias error: $err"
            exit 1
        }
        echo "$err" | grep -q "Registered aliases:" && {
            echo "registered aliases leaked at info: $err"
            exit 1
        }

        VOLUND_LOG_LEVEL=debug
        set +e
        err=$( ( volund_cmd nosuch true ) 2>&1 )
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || { echo "unknown alias should fail at debug"; exit 1; }
        echo "$err" | grep -q "Registered aliases:" || {
            echo "missing registered aliases at debug: $err"
            exit 1
        }
        echo "$err" | grep -q "myalias -> example.com/img:1" || {
            echo "missing alias mapping at debug: $err"
            exit 1
        }

        VOLUND_LOG_LEVEL=info
        set +e
        out=$( ( volund_main not_a_target ) 2>"$VOLUND_TMP_DIR/unk.err" )
        rc=$?
        set -e
        err=$(cat "$VOLUND_TMP_DIR/unk.err")
        [ "$rc" -ne 0 ] || { echo "unknown target should fail"; exit 1; }
        echo "$out" | grep -q 'Usage:' || { echo "unknown target should print help: $out"; exit 1; }
        echo "$out" | grep -q 'Available targets:' || { echo "help missing targets: $out"; exit 1; }
        echo "$out" | grep -q 'dummy_target' || { echo "help missing dummy_target: $out"; exit 1; }
        echo "$err" | grep -q "unknown target 'not_a_target'" || {
            echo "missing unknown target error: $err"
            exit 1
        }

        VOLUND_LOG_LEVEL=info
        v_foo=bar
        err=$(volund_save_var v_foo 2>&1)
        [ -z "$err" ] || { echo "save_var leaked at info: $err"; exit 1; }
        [ "$v_foo" = bar ] || { echo "save_var clobbered v_foo"; exit 1; }

        err=$(volund_env VOLUND_TEST_ENV_LOG 2>&1)
        [ -z "$err" ] || { echo "env leaked at info: $err"; exit 1; }

        # shellcheck disable=SC2034  # read by volund_log
        VOLUND_LOG_LEVEL=debug
        err=$(volund_save_var v_foo 2>&1)
        echo "$err" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z DEBUG save v_foo$' || {
            echo "missing save_var debug log: $err"
            exit 1
        }

        err=$(volund_env VOLUND_TEST_ENV_LOG_DEBUG 2>&1)
        echo "$err" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z DEBUG env VOLUND_TEST_ENV_LOG_DEBUG$' || {
            echo "missing env debug log: $err"
            exit 1
        }
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_volund_color() {
    local TEST_NAME="volund_color"
    start_test "$TEST_NAME"
    local failed=0
    (
        # NO_COLOR wins over a tty; FORCE_COLOR=0 alone still colors when stderr is a tty.
        # shellcheck disable=SC2034  # read by volund_color
        FORCE_COLOR=0
        # shellcheck disable=SC2034
        NO_COLOR=1
        out=$(volund_color red -- hello)
        [ "$out" = hello ] || { echo "color off should be plain: $out"; exit 1; }

        # shellcheck disable=SC2034
        FORCE_COLOR=1
        unset NO_COLOR
        out=$(volund_color red -- hello)
        echo "$out" | grep -q hello || { echo "missing text: $out"; exit 1; }
        echo "$out" | grep -q $'\033' || { echo "FORCE_COLOR wrap missing CSI: $out"; exit 1; }

        out=$(volund_color bold orange -- x)
        echo "$out" | grep -q x || { echo "missing bold orange text: $out"; exit 1; }

        out=$(volund_color dark grey -- g)
        echo "$out" | grep -q g || { echo "missing dark grey text: $out"; exit 1; }

        out=$(volund_color red hello)
        echo "$out" | grep -q hello || { echo "convenience form failed: $out"; exit 1; }

        set +e
        err=$( ( volund_color chartreuse -- x ) 2>&1 )
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || { echo "unknown color should fail"; exit 1; }
        echo "$err" | grep -qi "unknown attribute" || {
            echo "unknown color error: $err"
            exit 1
        }

        set +e
        err=$( ( volund_color red ) 2>&1 )
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || { echo "missing text should fail"; exit 1; }

        set +e
        err=$( ( volund_color dark light red -- x ) 2>&1 )
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || { echo "dark+light should fail"; exit 1; }
    ) || failed=1
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

# Run all
test_var_prefix_and_naming
test_load_save_no_export
test_cmd_real
test_script_real
test_prefix_change_and_validation_on_load
test_volund_with
test_volund_with_spaces
test_volund_log_and_help
test_volund_api_logs
test_volund_color

end_test_summary

# vi: filetype=sh expandtab sw=4
