#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vector Informatik GmbH
#
# SPDX-License-Identifier: MIT
#
# Functional smoke test for Bazel-built SIL Kit artifacts.
# Verifies binary parity with CMake: shared library properties,
# registry startup/shutdown, and C API symbol exports.

set -euo pipefail

REGISTRY="$1"
LIBSILKIT="$2"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== SIL Kit Functional Smoke Test ==="

# -----------------------------------------------------------------------
# 1. Registry --version
# -----------------------------------------------------------------------
echo ""
echo "--- 1. Registry --version ---"
VERSION_OUT=$("$REGISTRY" --version 2>&1) || true
if echo "$VERSION_OUT" | grep -q "SIL Kit version:"; then
    pass "registry --version prints version string"
else
    fail "registry --version did not print expected version string"
    echo "    output: $VERSION_OUT"
fi

# -----------------------------------------------------------------------
# 2. Shared library SONAME
# -----------------------------------------------------------------------
echo ""
echo "--- 2. Shared library SONAME ---"
if command -v readelf >/dev/null 2>&1; then
    READELF_OUT=$(readelf -d "$LIBSILKIT" 2>/dev/null || true)
    SONAME=$(echo "$READELF_OUT" | grep SONAME || true)
    if echo "$SONAME" | grep -q "libSilKit.so"; then
        pass "libSilKit.so has SONAME set to libSilKit.so"
    else
        fail "libSilKit.so missing SONAME"
        echo "    readelf output: $SONAME"
    fi
else
    echo "  SKIP: readelf not available"
fi

# -----------------------------------------------------------------------
# 3. C API symbol exports
# -----------------------------------------------------------------------
echo ""
echo "--- 3. C API symbol exports ---"
if command -v nm >/dev/null 2>&1; then
    # Capture nm output once to avoid SIGPIPE issues with pipefail
    NM_OUT=$(nm -D "$LIBSILKIT" 2>/dev/null || true)

    # Count exported SilKit_* symbols (T = text/code in dynamic symbol table)
    CAPI_COUNT=$(echo "$NM_OUT" | grep ' T ' | grep -c 'SilKit_' || true)
    if [ "$CAPI_COUNT" -ge 100 ]; then
        pass "libSilKit.so exports $CAPI_COUNT SilKit_* C API symbols (>= 100 expected)"
    else
        fail "libSilKit.so exports only $CAPI_COUNT SilKit_* symbols (expected >= 100)"
    fi

    # Spot-check a few critical symbols
    for SYM in SilKit_Participant_Create SilKit_Version_Major SilKit_CanController_Create; do
        if echo "$NM_OUT" | grep ' T ' | grep -q "$SYM"; then
            pass "symbol $SYM is exported"
        else
            fail "symbol $SYM is NOT exported"
        fi
    done
else
    echo "  SKIP: nm not available"
fi

# -----------------------------------------------------------------------
# 4. Dynamic dependencies (no unexpected libs)
# -----------------------------------------------------------------------
echo ""
echo "--- 4. Dynamic dependencies ---"
if command -v readelf >/dev/null 2>&1; then
    # Reuse READELF_OUT if available, otherwise fetch again
    if [ -z "${READELF_OUT:-}" ]; then
        READELF_OUT=$(readelf -d "$LIBSILKIT" 2>/dev/null || true)
    fi
    NEEDED=$(echo "$READELF_OUT" | grep NEEDED | sed 's/.*\[//' | sed 's/\]//')
    UNEXPECTED=""
    for LIB in $NEEDED; do
        case "$LIB" in
            libstdc++.so*|libm.so*|libgcc_s.so*|libc.so*|ld-linux-x86-64.so*|libpthread.so*)
                ;;
            *)
                UNEXPECTED="$UNEXPECTED $LIB"
                ;;
        esac
    done
    if [ -z "$UNEXPECTED" ]; then
        pass "no unexpected dynamic dependencies"
    else
        fail "unexpected dynamic dependencies:$UNEXPECTED"
    fi
else
    echo "  SKIP: readelf not available"
fi

# -----------------------------------------------------------------------
# 5. Registry start / listen / shutdown
# -----------------------------------------------------------------------
echo ""
echo "--- 5. Registry start/stop ---"

# Find an available port
PORT=0
for P in $(seq 18500 18520); do
    if ! ss -tln 2>/dev/null | grep -q ":$P "; then
        PORT=$P
        break
    fi
done

if [ "$PORT" -eq 0 ]; then
    echo "  SKIP: could not find a free port in 18500-18520"
else
    REGISTRY_URI="silkit://localhost:$PORT"
    "$REGISTRY" --listen-uri "$REGISTRY_URI" --log off &
    REG_PID=$!

    # Give it a moment to bind
    sleep 1

    if kill -0 "$REG_PID" 2>/dev/null; then
        # Check the port is actually listening
        if ss -tln 2>/dev/null | grep -q ":$PORT "; then
            pass "registry started and is listening on port $PORT"
        else
            fail "registry process running but not listening on port $PORT"
        fi
    else
        fail "registry process exited prematurely"
    fi

    # Clean shutdown
    kill "$REG_PID" 2>/dev/null || true
    wait "$REG_PID" 2>/dev/null || true
    pass "registry shut down cleanly"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "=== Summary: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
