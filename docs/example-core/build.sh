#!/bin/bash
# Minimal volund/lib/core demo: image alias, volund_cmd, volund_script,
# and persisted vars so you can re-run a single target later.
set -e

cd "$(dirname "$0")"
# shellcheck disable=SC1091  # relative to this file, not the repo root
. ../../lib/core

# Alias a container image. volund_cmd / volund_script use the alias, not the tag.
volund_image sh mirror.gcr.io/library/alpine:3.24.1

volund_default "clean init build verify"

clean() {
    volund_clean
    volund_cmd sh rm -rf dist
}

init() {
    # Saved under .volund/ and reloaded by later ./build.sh invocations.
    v_date=$(date --iso-8601=ns)
    echo "got timestamp $v_date"
    volund_save_var v_date
}

build() {
    # Quoted heredoc: $v_version expands inside the container (injected from .volund).
    echo "timestamp is $v_date"
    volund_script sh << 'VOLUND_EOF'
mkdir -p dist
printf 'hello at %s\n' "$v_date" > dist/hello
VOLUND_EOF
}

verify() {
    volund_cmd sh cat dist/hello
}

volund_main "$@"
