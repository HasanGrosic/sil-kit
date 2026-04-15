#!/bin/bash
# SPDX-FileCopyrightText: 2026 Vector Informatik GmbH
#
# SPDX-License-Identifier: MIT

# Test wrapper that symlinks data files flat into a temporary CWD and then
# executes the real test binary from that directory.
#
# Usage (via sh_test args):
#   run_with_data.sh <binary> [--subdir=<dir>|--flat|<file>] ...
#
# Plain arguments are symlinked by basename into the current target directory.
# --subdir=<dir> switches subsequent files into <dir>/ under the temp CWD.
# --flat resets back to the temp CWD root.

set -euo pipefail

BINARY="$1"
shift

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

SUBDIR=""

for arg in "$@"; do
    case "$arg" in
        --subdir=*)
            SUBDIR="${arg#--subdir=}"
            mkdir -p "$WORK_DIR/$SUBDIR"
            ;;
        --flat)
            SUBDIR=""
            ;;
        *)
            SRC=$(realpath "$arg")
            if [ -n "$SUBDIR" ]; then
                ln -sf "$SRC" "$WORK_DIR/$SUBDIR/$(basename "$arg")"
            else
                ln -sf "$SRC" "$WORK_DIR/$(basename "$arg")"
            fi
            ;;
    esac
done

# Resolve the binary to an absolute path before changing directory
BINARY_ABS=$(realpath "$OLDPWD/$BINARY" 2>/dev/null || realpath "$BINARY" 2>/dev/null)

cd "$WORK_DIR"
exec "$BINARY_ABS"
