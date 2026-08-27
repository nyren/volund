#!/bin/bash
#
# Build system for volund itself.
#
# Run tests and generate documentation SVGs.
#

set -e

cd "$(dirname "$0")"

. lib/core

FREEZE_VERSION="0.2.2"
FREEZE_DIGEST="012fdbdd16c0c19570f9052aac34d16d93d7d0d3b565b05374cc59492f53539b"

volund_image sh ghcr.io/nyren/volund-rc/volund-builder-sh:0.2.0-1

volund_default clean init lint build verify

clean() {
    volund_clean
    rm -rf .volund_test* .build
    rm -rf docs/example-core/.volund docs/example-core/dist
}

init() {
    mkdir -p .build

    # Determine download URL of freeze tool used to capture volund demos
    local freeze_arch=x86_64
    v_freeze_url="https://github.com/charmbracelet/freeze/releases/download/v${FREEZE_VERSION}/freeze_${FREEZE_VERSION}_Linux_${freeze_arch}.tar.gz"
    volund_save_var v_freeze_url
}

lint() {
    volund_cmd sh \
        shellcheck --shell=bash --external-sources -x -- \
        ./*.sh ./lib/* ./inc/* \
        ./tests/* ./docs/example-core/build.sh
}

build() {
    local demo_cmds="demo-core.txt"
    local demo_out=".build/example-core.out"
    local demo_svg=".build/example-core.svg"

    # Run demo commands and record output with colors enabled
    (
        cd docs/example-core
        export FORCE_COLOR=1
        export TERM=xterm-256color
        unset NO_COLOR
        while IFS= read -r line || [ -n "$line" ]; do
            if [ -z "$line" ]; then
                printf '\n'
                continue
            fi
            printf '$ %s\n' "$line"
            bash -lc "$line"
        done < "../$demo_cmds"
    ) > "$demo_out" 2>&1 || \
        volund_error "failed to record core demo: $(cat "$demo_out")"

    # Generate SVG of demo output
    volund_script sh "render demo SVG" << VOLUND_EOF
set -e
echo "Downloading charmbracelet/freeze ..."
curl -fsSL -o /tmp/freeze.tgz "$v_freeze_url"

echo "Verify checksums  ..."
cat << EOF > /tmp/checksums.txt
$FREEZE_DIGEST /tmp/freeze.tgz
EOF
sha256sum -c /tmp/checksums.txt

echo "Install freeze ..."
tar -xzf /tmp/freeze.tgz -C /tmp
install -m 755 /tmp/freeze_*/freeze /tmp/freeze

echo "Generate SVG ..."
/tmp/freeze --execute "cat $demo_out" \
    -c base \
    --output "$demo_svg"
VOLUND_EOF

    [ -s "$demo_svg" ] || \
        volund_error ".build/example-core.svg was not generated"
}

verify() {
    for t in tests/*.sh; do
        [ -f "$t" ] || continue
        case "$t" in
            */_helper.sh) continue ;;
        esac
        echo "==> $t"
        bash "$t"
    done
}

volund_main "$@"

# vi: filetype=sh expandtab sw=4
