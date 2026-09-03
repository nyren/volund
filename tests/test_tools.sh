#!/bin/bash
# High-level tests for volund/lib/tools.

set -eo pipefail
set +u

cd "$(dirname "$0")/.."
. lib/core
. lib/tools

. tests/_helper.sh

_make_sample_chart() {
    local chart="$1"
    mkdir -p "$chart/templates"
    cat > "$chart/Chart.yaml" << 'EOF'
apiVersion: v2
name: sample
description: test chart
type: application
version: 0.1.0
appVersion: "1.0.0"
annotations:
  example: __ANNOTATION__
EOF
    cat > "$chart/values.yaml" << 'EOF'
image:
  registry: __IMAGE_REGISTRY__
  tag: __IMAGE_VERSION__
EOF
    printf 'hello\n' > "$chart/templates/notes.txt"
}

test_tools_forwards_log_level() {
    local TEST_NAME="VOLUND_LOG_LEVEL available to volund-tools"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        export VOLUND_LOG_LEVEL=foobar
        set +e
        out=$(volund_version_dev 2>&1)
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || {
            echo "expected invalid VOLUND_LOG_LEVEL to fail: '$out'"
            exit 1
        }
        echo "$out" | grep -Fq "VOLUND_LOG_LEVEL: invalid value 'foobar'" || {
            echo "VOLUND_LOG_LEVEL not available in container: '$out'"
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

test_version_dev() {
    local TEST_NAME="volund_version_dev"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        out=$(volund_version_dev) || {
            echo "volund_version_dev failed"
            exit 1
        }
        echo "$out" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-h[0-9a-f]+' || {
            echo "invalid dev version: '$out'"
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

test_version_rc() {
    local TEST_NAME="volund_version_rc"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        set +e
        volund_repo_is_dirty
        dirty=$?
        set -e
        if [ "$dirty" -eq 0 ]; then
            set +e
            out=$(volund_version_rc 2>&1)
            rc=$?
            set -e
            [ "$rc" -ne 0 ] || {
                echo "expected dirty rc to fail, got: $out"
                exit 1
            }
        else
            out=$(volund_version_rc) || {
                echo "volund_version_rc failed"
                exit 1
            }
            echo "$out" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$' || {
                echo "invalid rc version: '$out'"
                exit 1
            }
        fi
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_version_release() {
    local TEST_NAME="volund_version_release"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        set +e
        volund_repo_is_dirty
        dirty=$?
        set -e
        if [ "$dirty" -eq 0 ]; then
            set +e
            out=$(volund_version_release 2>&1)
            rc=$?
            set -e
            [ "$rc" -ne 0 ] || {
                echo "expected dirty release to fail, got: $out"
                exit 1
            }
        else
            out=$(volund_version_release) || {
                echo "volund_version_release failed"
                exit 1
            }
            echo "$out" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$' || {
                echo "invalid release version: '$out'"
                exit 1
            }
        fi
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_version_increment() {
    local TEST_NAME="volund_version_increment"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        orig=$(cat VERSION)
        volund_version_increment patch || {
            echo "volund_version_increment failed"
            echo "$orig" > VERSION
            exit 1
        }
        new=$(cat VERSION)
        echo "$orig" > VERSION
        [ "$new" != "$orig" ] || {
            echo "increment did not change VERSION"
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

test_version_convert() {
    local TEST_NAME="volund_version_convert"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        out=$(volund_version_convert pep440 "1.0.0-3") || {
            echo "volund_version_convert failed"
            exit 1
        }
        echo "$out" | grep -q "1.0.0rc3" || {
            echo "invalid convert output: '$out'"
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

test_repo_get_branch() {
    local TEST_NAME="volund_repo_get_branch"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        out=$(volund_repo_get_branch) || {
            echo "volund_repo_get_branch failed"
            exit 1
        }
        [ -n "$out" ] || {
            echo "empty branch name"
            exit 1
        }
        echo "$out" | grep -qE '^[A-Za-z0-9._/-]+$' || {
            echo "invalid branch: '$out'"
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

test_repo_is_dirty_is_clean() {
    local TEST_NAME="volund_repo is-dirty / is-clean"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        set +e
        volund_repo_is_dirty
        dirty_rc=$?
        volund_repo_is_clean
        clean_rc=$?
        set -e
        [ "$dirty_rc" -ne "$clean_rc" ] || {
            echo "is-dirty ($dirty_rc) and is-clean ($clean_rc) should differ"
            exit 1
        }
        [ "$dirty_rc" -eq 0 ] || [ "$dirty_rc" -eq 1 ] || {
            echo "is-dirty unexpected rc $dirty_rc"
            exit 1
        }
        [ "$clean_rc" -eq 0 ] || [ "$clean_rc" -eq 1 ] || {
            echo "is-clean unexpected rc $clean_rc"
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

test_helm_package() {
    local TEST_NAME="volund_helm_package"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        chart="$VOLUND_TMP_DIR/sample"
        dest="$VOLUND_TMP_DIR/helm-out"
        _make_sample_chart "$chart"
        mkdir -p "$dest"
        unset HELM_CONFIG_HOME

        volund_helm_package "$chart" \
            --destination "$dest" \
            --version 1.2.3 \
            --app-version 9.9.9 \
            --replace __IMAGE_REGISTRY__=ghcr.io/example.com \
            --replace __IMAGE_VERSION__=1.2.3 \
            --replace __ANNOTATION__=replaced

        tgz="$dest/sample-1.2.3.tgz"
        [ -f "$tgz" ] || {
            echo "missing chart archive in $dest"
            ls -la "$dest" || true
            exit 1
        }

        extract="$VOLUND_TMP_DIR/extracted"
        mkdir -p "$extract"
        tar -xzf "$tgz" -C "$extract"
        values=$(cat "$extract/sample/values.yaml")
        chart_yaml=$(cat "$extract/sample/Chart.yaml")
        echo "$values" | grep -q 'ghcr.io/example.com' || {
            echo "registry not replaced: $values"
            exit 1
        }
        echo "$values" | grep -q '1.2.3' || {
            echo "image version not replaced: $values"
            exit 1
        }
        echo "$chart_yaml" | grep -q 'replaced' || {
            echo "annotation not replaced: $chart_yaml"
            exit 1
        }
        echo "$chart_yaml" | grep -q 'version: 1.2.3' || {
            echo "chart version not overridden: $chart_yaml"
            exit 1
        }
        echo "$chart_yaml" | grep -q 'appVersion:.*9.9.9' || {
            echo "appVersion not overridden: $chart_yaml"
            exit 1
        }
        echo "$values" | grep -q '__IMAGE_' && {
            echo "placeholder left in values: $values"
            exit 1
        }
        grep -q '__IMAGE_REGISTRY__' "$chart/values.yaml" || {
            echo "source values.yaml was mutated"
            exit 1
        }
        grep -q 'version: 0.1.0' "$chart/Chart.yaml" || {
            echo "source Chart.yaml was mutated"
            exit 1
        }

        # Same packaging through the helm-config volund_with path.
        HELM_CONFIG_HOME="$VOLUND_TMP_DIR/helm-config"
        mkdir -p "$HELM_CONFIG_HOME"
        dest2="$VOLUND_TMP_DIR/helm-out-config"
        volund_helm_package "$chart" \
            --destination "$dest2" \
            --version 2.0.0
        [ -f "$dest2/sample-2.0.0.tgz" ] || {
            echo "missing archive with HELM_CONFIG_HOME set"
            ls -la "$dest2" || true
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

test_helm_push_pull() {
    local TEST_NAME="volund_helm_push / pull"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        chart="$VOLUND_TMP_DIR/sample"
        dest="$VOLUND_TMP_DIR/helm-out"
        _make_sample_chart "$chart"
        mkdir -p "$dest"
        unset HELM_CONFIG_HOME

        volund_helm_package "$chart" --destination "$dest" --version 0.1.0
        tgz="$dest/sample-0.1.0.tgz"
        [ -f "$tgz" ] || {
            echo "package failed, cannot test push/pull"
            exit 1
        }

        set +e
        push_out=$(volund_helm_push "$tgz" oci://127.0.0.1:1/charts 2>&1)
        push_rc=$?
        pull_out=$(volund_helm_pull oci://127.0.0.1:1/charts/sample \
            --version 0.1.0 --destination "$dest" 2>&1)
        pull_rc=$?
        set -e

        [ "$push_rc" -ne 0 ] || {
            echo "push to closed port should fail: $push_out"
            exit 1
        }
        echo "$push_out" | grep -q 'cmd _tools helm push' || {
            echo "push did not run helm in tools container: $push_out"
            exit 1
        }
        [ "$pull_rc" -ne 0 ] || {
            echo "pull from closed port should fail: $pull_out"
            exit 1
        }
        echo "$pull_out" | grep -q 'cmd _tools helm pull' || {
            echo "pull did not run helm in tools container: $pull_out"
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

# Run all
test_tools_forwards_log_level
test_version_dev
test_version_rc
test_version_release
test_version_increment
test_version_convert
test_repo_get_branch
test_repo_is_dirty_is_clean
test_helm_package
test_helm_push_pull

end_test_summary

# vi: filetype=sh expandtab sw=4
