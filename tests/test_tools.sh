#!/bin/bash
# High-level tests for volund/lib/tools.

set -eo pipefail
set +u

cd "$(dirname "$0")/.."
. lib/core
. lib/tools

if [ -n "${VOLUND_TOOLS_IMAGE:-}" ]; then
    volund_image _tools "$VOLUND_TOOLS_IMAGE"
fi

. tests/_helper.sh

# Clean git repo: VERSION=1.2.3, then one commit that does not touch it.
# Count since the VERSION commit is therefore 1.
_tools_version_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git init -q -b main "$repo"
    printf '1.2.3\n' > "$repo/VERSION"
    git -C "$repo" add VERSION
    GIT_AUTHOR_NAME=VolundTest \
        GIT_AUTHOR_EMAIL=volund@test.example \
        GIT_COMMITTER_NAME=VolundTest \
        GIT_COMMITTER_EMAIL=volund@test.example \
        git -C "$repo" commit -q -m "add VERSION"
    printf 'x\n' > "$repo/unrelated.txt"
    git -C "$repo" add unrelated.txt
    GIT_AUTHOR_NAME=VolundTest \
        GIT_AUTHOR_EMAIL=volund@test.example \
        GIT_COMMITTER_NAME=VolundTest \
        GIT_COMMITTER_EMAIL=volund@test.example \
        git -C "$repo" commit -q -m "unrelated"
}

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

        local repo short out
        repo="$VOLUND_TMP_DIR/version-repo"
        _tools_version_repo "$repo"
        repo=$(cd "$repo" && pwd)
        short=$(git -C "$repo" rev-parse HEAD)
        short=${short:0:8}
        cd "$repo"

        out=$(volund_version_dev) || {
            echo "volund_version_dev failed"
            exit 1
        }
        [ "$out" = "1.2.3-1-h${short}" ] || {
            echo "invalid dev version: '$out'"
            exit 1
        }

        printf 'dirty\n' > dirty.txt
        # Podman --userns=keep-id fails if USER is not the invoking account.
        local user
        user=$(id -un)
        USER=$user
        export USER
        out=$(volund_version_dev) || {
            echo "dirty volund_version_dev failed"
            exit 1
        }
        [ "$out" = "1.2.3-1-h${short}-${user}" ] || {
            echo "invalid dirty dev version: '$out'"
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

        local repo out rc
        repo="$VOLUND_TMP_DIR/version-repo"
        _tools_version_repo "$repo"
        repo=$(cd "$repo" && pwd)
        cd "$repo"

        out=$(volund_version_rc) || {
            echo "volund_version_rc failed"
            exit 1
        }
        [ "$out" = "1.2.3-1" ] || {
            echo "invalid rc version: '$out'"
            exit 1
        }

        printf 'dirty\n' > dirty.txt
        set +e
        out=$(volund_version_rc 2>&1)
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || {
            echo "expected dirty rc to fail, got: $out"
            exit 1
        }
        echo "$out" | grep -q 'dirty rc version' || {
            echo "unexpected dirty rc error: $out"
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

test_version_release() {
    local TEST_NAME="volund_version_release"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        local repo out rc
        repo="$VOLUND_TMP_DIR/version-repo"
        _tools_version_repo "$repo"
        repo=$(cd "$repo" && pwd)
        cd "$repo"

        out=$(volund_version_release) || {
            echo "volund_version_release failed"
            exit 1
        }
        [ "$out" = "1.2.3" ] || {
            echo "invalid release version: '$out'"
            exit 1
        }

        printf 'dirty\n' > dirty.txt
        set +e
        out=$(volund_version_release 2>&1)
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || {
            echo "expected dirty release to fail, got: $out"
            exit 1
        }
        echo "$out" | grep -q 'dirty release version' || {
            echo "unexpected dirty release error: $out"
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

test_version_increment() {
    local TEST_NAME="volund_version_increment"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean

        local repo
        repo="$VOLUND_TMP_DIR/version-repo"
        _tools_version_repo "$repo"
        cd "$repo"

        volund_version_increment patch || {
            echo "volund_version_increment failed"
            exit 1
        }
        [ "$(cat VERSION)" = "1.2.4" ] || {
            echo "patch increment of 1.2.3 produced: $(cat VERSION)"
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

        local repo out
        repo="$VOLUND_TMP_DIR/branch-repo"
        mkdir -p "$repo"
        git init -q -b release-2 "$repo"
        printf '1.2.3\n' > "$repo/VERSION"
        git -C "$repo" add VERSION
        GIT_AUTHOR_NAME=VolundTest \
            GIT_AUTHOR_EMAIL=volund@test.example \
            GIT_COMMITTER_NAME=VolundTest \
            GIT_COMMITTER_EMAIL=volund@test.example \
            git -C "$repo" commit -q -m "add VERSION"
        cd "$repo"

        out=$(volund_repo_get_branch) || {
            echo "volund_repo_get_branch failed"
            exit 1
        }
        [ "$out" = "release-2" ] || {
            echo "unexpected branch: '$out'"
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

        local repo dirty_rc clean_rc
        repo="$VOLUND_TMP_DIR/version-repo"
        _tools_version_repo "$repo"
        cd "$repo"

        set +e
        volund_repo_is_dirty
        dirty_rc=$?
        volund_repo_is_clean
        clean_rc=$?
        set -e
        [ "$dirty_rc" -eq 1 ] || {
            echo "clean tree reported dirty: $dirty_rc"
            exit 1
        }
        [ "$clean_rc" -eq 0 ] || {
            echo "clean tree reported not clean: $clean_rc"
            exit 1
        }

        printf 'dirty\n' > dirty.txt
        set +e
        volund_repo_is_dirty
        dirty_rc=$?
        volund_repo_is_clean
        clean_rc=$?
        set -e
        [ "$dirty_rc" -eq 0 ] || {
            echo "dirty tree reported clean: $dirty_rc"
            exit 1
        }
        [ "$clean_rc" -eq 1 ] || {
            echo "dirty tree reported clean by is-clean: $clean_rc"
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
        echo "$push_out" | grep -q 'cmd _tools volund-tools helm push' || {
            echo "push did not run volund-tools helm push: $push_out"
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

_git_test_repo() {
    repo="$VOLUND_TMP_DIR/repo"
    bare="$VOLUND_TMP_DIR/bare.git"
    mkdir -p "$repo" "$bare"
    git init -q -b main "$repo"
    git init -q --bare "$bare"
    repo=$(cd "$repo" && pwd)
    bare=$(cd "$bare" && pwd)
    printf '1.0.0\n' > "$repo/VERSION"
    git -C "$repo" add VERSION
    git -C "$repo" remote add origin "$bare"
    export GIT_AUTHOR_NAME=VolundTest
    export GIT_AUTHOR_EMAIL=volund@test.example
    export GIT_COMMITTER_NAME=VolundTest
    export GIT_COMMITTER_EMAIL=volund@test.example
}

test_volund_git_commit_and_push() {
    local TEST_NAME="volund_git commit and local push"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        unset VOLUND_GIT_CREDENTIALS
        _git_test_repo

        volund_git -C "$repo" commit -m "test commit"
        volund_git -C "$repo" push origin HEAD

        log=$(git --git-dir="$bare" log -1 --format='%an <%ae> %s' main)
        echo "$log" | grep -q 'VolundTest <volund@test.example> test commit' || {
            echo "unexpected commit in bare repo: $log"
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

# ls-remote via a stand-in ssh that records the passwd home and the
# known_hosts path OpenSSH would use. The stand-in exits 1; the result file
# is the assertion source.
_volund_git_ssh_probe() {
    local out="$1"
    local probe
    probe="$(mktemp -p "$VOLUND_TMP_DIR" ssh-probe.XXXXXX)"
    cat > "$probe" << EOF
#!/bin/sh
uid=\$(id -u)
phome=\$(awk -F: -v u="\$uid" '\$3==u {print \$6; exit}' /etc/passwd)
{
    printf 'passwd_home=%s\n' "\$phome"
    printf 'env_home=%s\n' "\${HOME-}"
    if [ -f "\$phome/.ssh/known_hosts" ]; then
        printf 'marker=%s\n' "\$(cat "\$phome/.ssh/known_hosts")"
    else
        printf 'marker=MISSING\n'
    fi
    ssh -G git@example.test 2>/dev/null | awk '/^userknownhostsfile /{print; exit}'
} > "$out"
exit 1
EOF
    chmod 755 "$probe"
    probe="$(cd "$(dirname "$probe")" && pwd)/$(basename "$probe")"
    unset GIT_SSH_COMMAND
    set +e
    volund_git -c core.sshCommand="$probe" ls-remote git@example.test:org/repo >/dev/null 2>&1
    set -e
    [ -s "$out" ] || test_error "ssh probe did not run"
}

test_volund_git_known_hosts_prepared_home() {
    local TEST_NAME="volund_git ssh known_hosts follows prepared HOME"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    local home real_home xdg_data xdg_config
    home="$(mktemp -d /tmp/volund-home.XXXXXX)"
    # Podman stores images under $HOME. Pin the real XDG dirs before HOME
    # points at the fixture, or the runtime looks for its storage there.
    real_home="${HOME}"
    xdg_data="${XDG_DATA_HOME:-$real_home/.local/share}"
    xdg_config="${XDG_CONFIG_HOME:-$real_home/.config}"
    (
        volund_clean
        mkdir -p "$home/.ssh"
        printf 'volund-known-hosts-marker\n' > "$home/.ssh/known_hosts"
        export XDG_DATA_HOME="$xdg_data"
        export XDG_CONFIG_HOME="$xdg_config"
        export HOME="$home"

        local out line passwd_home env_home marker kh
        out="$VOLUND_TMP_DIR/ssh-probe.out"
        out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
        VOLUND_GIT_CREDENTIALS=auto _volund_git_ssh_probe "$out"

        passwd_home=
        env_home=
        marker=
        kh=
        while IFS= read -r line; do
            case "$line" in
                passwd_home=*) passwd_home=${line#passwd_home=} ;;
                env_home=*) env_home=${line#env_home=} ;;
                marker=*) marker=${line#marker=} ;;
                userknownhostsfile\ *) kh=${line#userknownhostsfile } ;;
            esac
        done < "$out"
        [ "$passwd_home" = "$home" ] || test_error "passwd home is '$passwd_home'"
        [ "$env_home" = "$home" ] || test_error "container HOME is '$env_home'"
        [ "$marker" = "volund-known-hosts-marker" ] || test_error "known_hosts marker is '$marker'"
        [ "$kh" = "$home/.ssh/known_hosts $home/.ssh/known_hosts2" ] || \
            test_error "ssh known_hosts path is '$kh'"
    ) || failed=1
    rm -rf "$home"
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_volund_git_requires_home() {
    local TEST_NAME="volund_git requires HOME"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        unset HOME
        local out rc
        set +e
        out=$(volund_git status 2>&1)
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || test_error "volund_git succeeded without HOME"
        echo "$out" | grep -q 'volund_git: HOME is not set' || \
            test_error "missing HOME error: $out"
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_volund_helm_requires_home() {
    local TEST_NAME="volund_helm requires HOME"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        unset HOME
        local out rc
        set +e
        out=$(volund_helm_package . 2>&1)
        rc=$?
        set -e
        [ "$rc" -ne 0 ] || test_error "volund_helm_package succeeded without HOME"
        echo "$out" | grep -q 'volund_helm: HOME is not set' || \
            test_error "missing HOME error: $out"
    ) || failed=1
    cleanup_test_volund $failed
    if [ $failed -eq 0 ]; then
        pass_test "$TEST_NAME"
    else
        fail_test "$TEST_NAME"
    fi
}

test_volund_git_auto_push() {
    local TEST_NAME="volund_git auto credentials local push"
    start_test "$TEST_NAME"
    local failed=0
    setup_test_volund
    (
        volund_clean
        _git_test_repo

        volund_git -C "$repo" commit -m "test commit"
        VOLUND_GIT_CREDENTIALS=auto volund_git -C "$repo" push origin HEAD

        log=$(git --git-dir="$bare" log -1 --format='%s' main)
        echo "$log" | grep -q 'test commit' || {
            echo "auto push did not land commit: $log"
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
test_volund_git_commit_and_push
test_volund_git_known_hosts_prepared_home
test_volund_git_requires_home
test_volund_helm_requires_home
test_volund_git_auto_push

end_test_summary

# vi: filetype=sh expandtab sw=4
