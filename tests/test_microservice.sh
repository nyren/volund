#!/bin/bash
# High-level tests for volund/lib/microservice.
# Exercises the functions and checks the resulting shell variables
# (and side effects) rather than just function presence.

set -eo pipefail
set +u

cd "$(dirname "$0")/.."

. lib/core
. lib/tools
. lib/microservice

. tests/_helper.sh

_ms_defaults() {
    DEFAULT_REGISTRY="reg.example.com"
    # shellcheck disable=SC2034  # read by set_repo_*
    DEFAULT_REPO_PATH_DEV="myorg/dev"
    # shellcheck disable=SC2034
    DEFAULT_REPO_PATH_CI="myorg/ci"
    # shellcheck disable=SC2034
    DEFAULT_REPO_PATH_RC="myorg"
    # shellcheck disable=SC2034
    DEFAULT_REPO_PATH_RELEASE="myorg"
}

test_microservice_set_version_dev() {
    local TEST_NAME="set_version_dev produce valid version"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        v_version=""
        set_version_dev || echo "set_version_dev failed"

        echo "$v_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-h[0-9a-f]+' || {
            echo "invalid version: '$v_version'"
            exit 1
        }

        local version_persisted
        version_persisted=$(cat "$VOLUND_VAR_DIR/var.v_version")
        [ "$version_persisted" = "$v_version" ] || {
            echo "invalid persisted version: '$version_persisted'"
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

test_microservice_repo_charts_only() {
    local TEST_NAME="repo computation (charts only)"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    v_version="1.2.3"
    (
        volund_clean
        _ms_defaults
        unset REGISTRY REPO_PATH REPO_PATH_DEV REPO_PATH_CI REPO_PATH_RC REPO_PATH_RELEASE

        CHARTS[api]="api"
        CHARTS[worker]="worker"

        set_repo_dev
        [ "$v_registry" = "reg.example.com" ] || { echo "bad registry: $v_registry"; exit 1; }
        [ "$v_repo_path" = "myorg/dev" ] || { echo "bad dev repo path: $v_repo_path"; exit 1; }
        [ "$v_chart_repo" = "oci://reg.example.com/myorg/dev/charts" ] || {
            echo "bad chart repo: $v_chart_repo"
            exit 1
        }
        [ "${v_api_chart_dir:-}" = "charts/api" ] || {
            echo "bad api chart dir: ${v_api_chart_dir}"
            exit 1
        }
        [ "${v_api_chart_path:-}" = ".build/api-1.2.3.tgz" ] || {
            echo "bad api chart path: ${v_api_chart_path}"
            exit 1
        }
        [ "${v_worker_chart_path:-}" = ".build/worker-1.2.3.tgz" ] || {
            echo "bad worker chart path: ${v_worker_chart_path}"
            exit 1
        }
        [ -z "${v_api_chart_url:-}" ] || {
            echo "chart url should not be set: ${v_api_chart_url}"
            exit 1
        }

        set_repo_ci
        [ "$v_repo_path" = "myorg/ci" ] || { echo "bad ci repo path: $v_repo_path"; exit 1; }

        set_repo_rc
        [ "$v_repo_path" = "myorg" ] || { echo "bad rc repo path: $v_repo_path"; exit 1; }

        set_repo_release
        [ "$v_repo_path" = "myorg" ] || { echo "bad release repo path: $v_repo_path"; exit 1; }
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_microservice_repo_with_images() {
    local TEST_NAME="repo computation (with images)"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    v_version="0.9.0-rc.1"
    (
        volund_clean
        _ms_defaults
        unset REGISTRY REPO_PATH REPO_PATH_DEV

        CHARTS[api]="api"
        IMAGES[api]="api-svc"
        IMAGES[worker]="worker-svc"

        oci_tag=$(volund_version_convert oci-tag "0.9.0-rc.1")
        set_repo_dev

        [ "$v_repo_path" = "myorg/dev" ] || { echo "bad repo path"; exit 1; }
        [ "${v_api_chart_dir:-}" = "charts/api" ] || {
            echo "bad chart dir: ${v_api_chart_dir}"
            exit 1
        }
        [ "${v_api_chart_path:-}" = ".build/api-0.9.0-rc.1.tgz" ] || {
            echo "bad chart path: ${v_api_chart_path}"
            exit 1
        }
        [ -z "${v_api_chart_url:-}" ] || {
            echo "chart url should not be set: ${v_api_chart_url}"
            exit 1
        }
        [ "${v_api_image_ref:-}" = "reg.example.com/myorg/dev/api-svc:${oci_tag}" ] || {
            echo "bad api image ref: ${v_api_image_ref}"
            exit 1
        }
        [ "${v_worker_image_ref:-}" = "reg.example.com/myorg/dev/worker-svc:${oci_tag}" ] || {
            echo "bad worker image ref: ${v_worker_image_ref}"
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

test_microservice_overrides() {
    local TEST_NAME="REGISTRY / REPO_PATH overrides"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    v_version="1.0.0"
    (
        volund_clean
        _ms_defaults
        CHARTS[api]="api"

        REGISTRY=ghcr.io/alice
        unset REPO_PATH REPO_PATH_DEV
        set_repo_dev
        [ "$v_registry" = "ghcr.io/alice" ] || { echo "REGISTRY override lost: $v_registry"; exit 1; }
        [ "$v_repo_path" = "myorg/dev" ] || { echo "default path lost: $v_repo_path"; exit 1; }

        unset REGISTRY
        REPO_PATH=alice
        set_repo_dev
        [ "$v_registry" = "reg.example.com" ] || { echo "default registry lost: $v_registry"; exit 1; }
        [ "$v_repo_path" = "alice" ] || { echo "REPO_PATH override lost: $v_repo_path"; exit 1; }
        set_repo_rc
        [ "$v_repo_path" = "alice" ] || { echo "REPO_PATH should apply to rc: $v_repo_path"; exit 1; }

        # shellcheck disable=SC2034  # read by set_repo_dev
        REPO_PATH_DEV=alice-dev
        set_repo_dev
        [ "$v_repo_path" = "alice-dev" ] || { echo "REPO_PATH_DEV should win: $v_repo_path"; exit 1; }
        set_repo_ci
        [ "$v_repo_path" = "alice" ] || { echo "ci should still use REPO_PATH: $v_repo_path"; exit 1; }

        pers=$(cat "$VOLUND_VAR_DIR/var.v_registry")
        [ "$pers" = "reg.example.com" ] || { echo "v_registry not persisted: $pers"; exit 1; }
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_microservice_invalid_key() {
    local TEST_NAME="CHARTS key must be an identifier"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    v_version="1.0.0"
    (
        volund_clean
        _ms_defaults
        CHARTS['bad-key']="chart"
        set +e
        err=$(set_repo_dev 2>&1)
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || { echo "expected invalid key to fail: $err"; exit 1; }
        echo "$err" | grep -q "not a valid identifier" || {
            echo "missing identifier error: $err"
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

test_microservice_set_version_variants() {
    local TEST_NAME="set_version_* variants"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    v_version=
    (
        volund_clean

        set_version_dev || test_error "set_version_dev failed"
        echo "$v_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-h[0-9a-f]+' || \
            test_error "invalid dev version: '$v_version'"

        set +e
        volund_repo_is_dirty
        dirty=$?
        set -e

        if [ "$dirty" -eq 0 ]; then
            set +e
            volund_version_rc >/dev/null 2>&1
            rc=$?
            set -e
            [ "$rc" -ne 0 ] || test_error "volund_version_rc should fail when dirty"
            set +e
            volund_version_release >/dev/null 2>&1
            rc=$?
            set -e
            [ "$rc" -ne 0 ] || test_error "volund_version_release should fail when dirty"
        else
            set_version_rc || test_error "set_version_rc failed"
            echo "$v_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$' || \
                test_error "invalid rc version: '$v_version'"

            set_version_release || test_error "set_version_release failed"
            echo "$v_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$' || \
                test_error "invalid release version: '$v_version'"
        fi
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_microservice_chart_path_build_metadata() {
    local TEST_NAME="chart path keeps + from version"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    v_version="1.2.3+4"
    (
        volund_clean
        _ms_defaults
        unset REGISTRY REPO_PATH REPO_PATH_DEV
        CHARTS[service]="myapp"
        set_repo_dev
        [ "${v_service_chart_path:-}" = ".build/myapp-1.2.3+4.tgz" ] || {
            echo "build metadata lost in chart path: ${v_service_chart_path}"
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

test_microservice_publish_charts() {
    local TEST_NAME="publish_charts saves oci url and digest"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    v_version="1.2.3"
    (
        volund_clean
        _ms_defaults
        unset REGISTRY REPO_PATH REPO_PATH_DEV
        CHARTS[service]="myapp"
        set_repo_dev

        mkdir -p .build
        printf 'chart\n' > "$v_service_chart_path"
        trap 'rm -f "$v_service_chart_path"; rmdir .build 2>/dev/null || true' EXIT

        volund_helm_push() {
            local chart=$1 remote=$2
            shift 2
            local ref_file="" digest_file=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --oci-ref-file)
                        ref_file=$2
                        shift 2
                        ;;
                    --oci-digest-file)
                        digest_file=$2
                        shift 2
                        ;;
                    *)
                        echo "unexpected helm push arg: $1"
                        return 1
                        ;;
                esac
            done
            [ "$chart" = ".build/myapp-1.2.3.tgz" ] || {
                echo "bad chart arg: $chart"
                return 1
            }
            [ "$remote" = "oci://reg.example.com/myorg/dev/charts" ] || {
                echo "bad remote: $remote"
                return 1
            }
            [ -n "$ref_file" ] && [ -n "$digest_file" ] || {
                echo "missing oci files"
                return 1
            }
            printf 'reg.example.com/myorg/dev/charts/myapp:1.2.3\n' > "$ref_file"
            printf 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$digest_file"
        }

        publish_charts

        [ "${v_service_chart_url:-}" = "oci://reg.example.com/myorg/dev/charts/myapp:1.2.3" ] || {
            echo "bad chart url: ${v_service_chart_url:-}"
            exit 1
        }
        [ -z "${v_service_chart_ref:-}" ] || {
            echo "bare chart ref should not be saved: ${v_service_chart_ref}"
            exit 1
        }
        [ "${v_service_chart_digest:-}" = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ] || {
            echo "bad chart digest: ${v_service_chart_digest:-}"
            exit 1
        }
        pers=$(cat "$VOLUND_VAR_DIR/var.v_service_chart_url")
        [ "$pers" = "$v_service_chart_url" ] || {
            echo "chart url not persisted: $pers"
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

test_microservice_publish_images() {
    local TEST_NAME="publish_images pushes image refs"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    v_version="1.0.0"
    (
        volund_clean
        _ms_defaults
        unset REGISTRY REPO_PATH REPO_PATH_DEV
        IMAGES[main]="svc"
        IMAGES[init]="svc-init"
        set_repo_dev

        pushed="$VOLUND_TMP_DIR/pushed"
        : > "$pushed"
        volund_runtime() {
            echo "$*" >> "$pushed"
        }

        publish_images

        grep -qx "push ${v_main_image_ref:-}" "$pushed" || {
            echo "main image not pushed: $(cat "$pushed")"
            exit 1
        }
        grep -qx "push ${v_init_image_ref:-}" "$pushed" || {
            echo "init image not pushed: $(cat "$pushed")"
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

test_microservice_bump_version_gates() {
    local TEST_NAME="bump_version rejects unofficial/dirty tree"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        # Untracked file in the repo root. .volund_test* and .build are gitignored,
        # so a marker there would not make the tree dirty.
        marker="bump-version-test-dirty"
        trap 'rm -f "$marker"' EXIT
        echo dirty > "$marker"
        set +e
        err=$(bump_version 2>&1)
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || { echo "bump_version should fail here: $err"; exit 1; }
        echo "$err" | grep -qE 'modified files present|not an official branch|not up-to-date' || {
            echo "unexpected bump_version error: $err"
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
test_microservice_set_version_dev
test_microservice_repo_charts_only
test_microservice_repo_with_images
test_microservice_overrides
test_microservice_invalid_key
test_microservice_set_version_variants
test_microservice_chart_path_build_metadata
test_microservice_publish_charts
test_microservice_publish_images
test_microservice_bump_version_gates

end_test_summary

# vi: filetype=sh expandtab sw=4
