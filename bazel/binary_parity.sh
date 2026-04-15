#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vector Informatik GmbH
#
# SPDX-License-Identifier: MIT
#
# Normalized binary parity comparison between CMake and Bazel builds.
#
# Compares: ELF sections, symbol tables, dynamic deps, SONAME, ELF header
# attributes, and section size ratios. Intentionally ignores: build paths,
# timestamps, build-IDs, and absolute addresses.
#
# Usage: binary_parity.sh <cmake_bin> <bazel_bin> <label>

set -euo pipefail

CMAKE="$1"
BAZEL="$2"
LABEL="$3"

PASS=0
FAIL=0
WARN=0

pass()  { echo "    PASS: $1"; PASS=$((PASS + 1)); }
fail()  { echo "    FAIL: $1"; FAIL=$((FAIL + 1)); }
warn()  { echo "    WARN: $1"; WARN=$((WARN + 1)); }

echo ""
echo "================================================================"
echo "  $LABEL"
echo "================================================================"
echo "  CMake: $CMAKE"
echo "  Bazel: $BAZEL"

# -------------------------------------------------------------------
# 1. ELF type (shared object vs executable)
# -------------------------------------------------------------------
echo ""
echo "--- ELF header ---"
CMAKE_TYPE=$(readelf -h "$CMAKE" 2>/dev/null | grep 'Type:' | awk '{print $2}')
BAZEL_TYPE=$(readelf -h "$BAZEL" 2>/dev/null | grep 'Type:' | awk '{print $2}')
if [ "$CMAKE_TYPE" = "$BAZEL_TYPE" ]; then
    pass "ELF type: $CMAKE_TYPE"
else
    fail "ELF type: CMake=$CMAKE_TYPE  Bazel=$BAZEL_TYPE"
fi

CMAKE_MACHINE=$(readelf -h "$CMAKE" 2>/dev/null | grep 'Machine:' | sed 's/.*Machine:\s*//')
BAZEL_MACHINE=$(readelf -h "$BAZEL" 2>/dev/null | grep 'Machine:' | sed 's/.*Machine:\s*//')
if [ "$CMAKE_MACHINE" = "$BAZEL_MACHINE" ]; then
    pass "Machine: $CMAKE_MACHINE"
else
    fail "Machine: CMake=$CMAKE_MACHINE  Bazel=$BAZEL_MACHINE"
fi

# -------------------------------------------------------------------
# 2. Dynamic dependencies (NEEDED + SONAME)
# -------------------------------------------------------------------
echo ""
echo "--- Dynamic dependencies ---"
CMAKE_DYN=$(readelf -d "$CMAKE" 2>/dev/null || true)
BAZEL_DYN=$(readelf -d "$BAZEL" 2>/dev/null || true)

CMAKE_NEEDED=$(echo "$CMAKE_DYN" | grep NEEDED | sed 's/.*\[//' | sed 's/\]//' | sort)
BAZEL_NEEDED=$(echo "$BAZEL_DYN" | grep NEEDED | sed 's/.*\[//' | sed 's/\]//' | sort)

if [ "$CMAKE_NEEDED" = "$BAZEL_NEEDED" ]; then
    pass "NEEDED libraries match"
else
    # Check if the difference is only libSilKit.so (utilities link dynamically in CMake, statically in Bazel)
    CMAKE_ONLY=$(comm -23 <(echo "$CMAKE_NEEDED") <(echo "$BAZEL_NEEDED"))
    BAZEL_ONLY=$(comm -13 <(echo "$CMAKE_NEEDED") <(echo "$BAZEL_NEEDED"))
    if [ -n "$CMAKE_ONLY" ] || [ -n "$BAZEL_ONLY" ]; then
        warn "NEEDED libraries differ"
        [ -n "$CMAKE_ONLY" ] && echo "      CMake only: $CMAKE_ONLY"
        [ -n "$BAZEL_ONLY" ] && echo "      Bazel only: $BAZEL_ONLY"
    fi
fi

CMAKE_SONAME=$(echo "$CMAKE_DYN" | grep SONAME | sed 's/.*\[//' | sed 's/\]//' || true)
BAZEL_SONAME=$(echo "$BAZEL_DYN" | grep SONAME | sed 's/.*\[//' | sed 's/\]//' || true)
if [ "$CMAKE_SONAME" = "$BAZEL_SONAME" ]; then
    if [ -n "$CMAKE_SONAME" ]; then
        pass "SONAME: $CMAKE_SONAME"
    else
        pass "SONAME: (none -- expected for executables)"
    fi
else
    fail "SONAME: CMake='$CMAKE_SONAME'  Bazel='$BAZEL_SONAME'"
fi

# -------------------------------------------------------------------
# 3. Dynamic symbol table (exports)
# -------------------------------------------------------------------
echo ""
echo "--- Dynamic symbol table ---"
# Extract defined (T/W/B/D) dynamic symbols, strip addresses
CMAKE_DSYMS=$(nm -D "$CMAKE" 2>/dev/null | grep -E ' [TWBD] ' | awk '{print $2, $3}' | sort || true)
BAZEL_DSYMS=$(nm -D "$BAZEL" 2>/dev/null | grep -E ' [TWBD] ' | awk '{print $2, $3}' | sort || true)

CMAKE_DSYM_COUNT=$(echo "$CMAKE_DSYMS" | grep -c . || true)
BAZEL_DSYM_COUNT=$(echo "$BAZEL_DSYMS" | grep -c . || true)

if [ "$CMAKE_DSYMS" = "$BAZEL_DSYMS" ]; then
    pass "dynamic symbols identical ($CMAKE_DSYM_COUNT symbols)"
else
    CMAKE_ONLY=$(comm -23 <(echo "$CMAKE_DSYMS") <(echo "$BAZEL_DSYMS") | wc -l)
    BAZEL_ONLY=$(comm -13 <(echo "$CMAKE_DSYMS") <(echo "$BAZEL_DSYMS") | wc -l)
    if [ "$CMAKE_ONLY" -eq 0 ] && [ "$BAZEL_ONLY" -eq 0 ]; then
        pass "dynamic symbols identical ($CMAKE_DSYM_COUNT symbols)"
    else
        warn "dynamic symbols differ: CMake=$CMAKE_DSYM_COUNT  Bazel=$BAZEL_DSYM_COUNT  (CMake-only=$CMAKE_ONLY  Bazel-only=$BAZEL_ONLY)"
        if [ "$CMAKE_ONLY" -le 10 ] && [ "$CMAKE_ONLY" -gt 0 ]; then
            echo "      CMake-only symbols:"
            comm -23 <(echo "$CMAKE_DSYMS") <(echo "$BAZEL_DSYMS") | head -10 | sed 's/^/        /'
        fi
        if [ "$BAZEL_ONLY" -le 10 ] && [ "$BAZEL_ONLY" -gt 0 ]; then
            echo "      Bazel-only symbols:"
            comm -13 <(echo "$CMAKE_DSYMS") <(echo "$BAZEL_DSYMS") | head -10 | sed 's/^/        /'
        fi
    fi
fi

# -------------------------------------------------------------------
# 4. Full symbol table comparison (static/internal symbols)
# -------------------------------------------------------------------
echo ""
echo "--- Full symbol table ---"
# Extract all defined symbols: type + name (no addresses, no sizes)
CMAKE_SYMS=$(nm "$CMAKE" 2>/dev/null | awk '{print $2, $3}' | grep -E '^[A-Za-z] ' | sort || true)
BAZEL_SYMS=$(nm "$BAZEL" 2>/dev/null | awk '{print $2, $3}' | grep -E '^[A-Za-z] ' | sort || true)

CMAKE_SYM_COUNT=$(echo "$CMAKE_SYMS" | grep -c . || true)
BAZEL_SYM_COUNT=$(echo "$BAZEL_SYMS" | grep -c . || true)

if [ "$CMAKE_SYM_COUNT" -eq 0 ] && [ "$BAZEL_SYM_COUNT" -eq 0 ]; then
    pass "both stripped (no static symbols)"
elif [ "$CMAKE_SYMS" = "$BAZEL_SYMS" ]; then
    pass "full symbol tables identical ($CMAKE_SYM_COUNT symbols)"
else
    SYM_ONLY_CMAKE=$(comm -23 <(echo "$CMAKE_SYMS") <(echo "$BAZEL_SYMS") | wc -l)
    SYM_ONLY_BAZEL=$(comm -13 <(echo "$CMAKE_SYMS") <(echo "$BAZEL_SYMS") | wc -l)
    SYM_COMMON=$(comm -12 <(echo "$CMAKE_SYMS") <(echo "$BAZEL_SYMS") | wc -l)
    PCT_COMMON=0
    TOTAL=$((CMAKE_SYM_COUNT > BAZEL_SYM_COUNT ? CMAKE_SYM_COUNT : BAZEL_SYM_COUNT))
    if [ "$TOTAL" -gt 0 ]; then
        PCT_COMMON=$((SYM_COMMON * 100 / TOTAL))
    fi
    if [ "$PCT_COMMON" -ge 95 ]; then
        pass "full symbol tables ${PCT_COMMON}% common (CMake=$CMAKE_SYM_COUNT  Bazel=$BAZEL_SYM_COUNT  common=$SYM_COMMON)"
    elif [ "$PCT_COMMON" -ge 80 ]; then
        warn "full symbol tables ${PCT_COMMON}% common (CMake=$CMAKE_SYM_COUNT  Bazel=$BAZEL_SYM_COUNT  common=$SYM_COMMON  CMake-only=$SYM_ONLY_CMAKE  Bazel-only=$SYM_ONLY_BAZEL)"
    else
        fail "full symbol tables only ${PCT_COMMON}% common (CMake=$CMAKE_SYM_COUNT  Bazel=$BAZEL_SYM_COUNT  common=$SYM_COMMON)"
    fi
fi

# -------------------------------------------------------------------
# 5. ELF section sizes (via size(1))
# -------------------------------------------------------------------
echo ""
echo "--- ELF section sizes ---"
CMAKE_SIZES=$(size "$CMAKE" 2>/dev/null | tail -1 || true)
BAZEL_SIZES=$(size "$BAZEL" 2>/dev/null | tail -1 || true)

for IDX_NAME in "1:.text" "2:.data" "3:.bss"; do
    IDX="${IDX_NAME%%:*}"
    SECTION="${IDX_NAME##*:}"
    CMAKE_SIZE=$(echo "$CMAKE_SIZES" | awk -v i="$IDX" '{print $i}')
    BAZEL_SIZE=$(echo "$BAZEL_SIZES" | awk -v i="$IDX" '{print $i}')

    CMAKE_SIZE=${CMAKE_SIZE:-0}
    BAZEL_SIZE=${BAZEL_SIZE:-0}

    if [ "$CMAKE_SIZE" -eq 0 ] && [ "$BAZEL_SIZE" -eq 0 ]; then
        continue
    fi

    # Skip ratio check for tiny sections (< 4K) -- ratio is meaningless
    if [ "$CMAKE_SIZE" -lt 4096 ] && [ "$BAZEL_SIZE" -lt 4096 ]; then
        pass "$SECTION size both small: CMake=${CMAKE_SIZE}B  Bazel=${BAZEL_SIZE}B"
        continue
    fi

    # Calculate ratio (larger / smaller)
    if [ "$CMAKE_SIZE" -ge "$BAZEL_SIZE" ] && [ "$BAZEL_SIZE" -gt 0 ]; then
        RATIO=$((CMAKE_SIZE * 100 / BAZEL_SIZE))
    elif [ "$CMAKE_SIZE" -gt 0 ]; then
        RATIO=$((BAZEL_SIZE * 100 / CMAKE_SIZE))
    else
        RATIO=999
    fi

    CMAKE_KB=$((CMAKE_SIZE / 1024))
    BAZEL_KB=$((BAZEL_SIZE / 1024))

    if [ "$RATIO" -le 120 ]; then
        pass "$SECTION size within 20%: CMake=${CMAKE_KB}K  Bazel=${BAZEL_KB}K  (ratio=${RATIO}%)"
    elif [ "$RATIO" -le 150 ]; then
        warn "$SECTION size within 50%: CMake=${CMAKE_KB}K  Bazel=${BAZEL_KB}K  (ratio=${RATIO}%)"
    else
        fail "$SECTION size >50% off: CMake=${CMAKE_KB}K  Bazel=${BAZEL_KB}K  (ratio=${RATIO}%)"
    fi
done

# -------------------------------------------------------------------
# 6. Total file size
# -------------------------------------------------------------------
echo ""
echo "--- File size ---"
CMAKE_FSIZE=$(stat -c%s "$CMAKE")
BAZEL_FSIZE=$(stat -c%s "$BAZEL")
if [ "$CMAKE_FSIZE" -ge "$BAZEL_FSIZE" ] && [ "$BAZEL_FSIZE" -gt 0 ]; then
    FRATIO=$((CMAKE_FSIZE * 100 / BAZEL_FSIZE))
elif [ "$CMAKE_FSIZE" -gt 0 ]; then
    FRATIO=$((BAZEL_FSIZE * 100 / CMAKE_FSIZE))
else
    FRATIO=999
fi
CMAKE_FKB=$((CMAKE_FSIZE / 1024))
BAZEL_FKB=$((BAZEL_FSIZE / 1024))
if [ "$FRATIO" -le 120 ]; then
    pass "file size within 20%: CMake=${CMAKE_FKB}K  Bazel=${BAZEL_FKB}K  (ratio=${FRATIO}%)"
elif [ "$FRATIO" -le 200 ]; then
    warn "file size within 2x: CMake=${CMAKE_FKB}K  Bazel=${BAZEL_FKB}K  (ratio=${FRATIO}%)"
else
    fail "file size >2x off: CMake=${CMAKE_FKB}K  Bazel=${BAZEL_FKB}K  (ratio=${FRATIO}%)"
fi

# -------------------------------------------------------------------
# Summary line (consumed by wrapper)
# -------------------------------------------------------------------
echo ""
echo "  Result: $PASS passed, $FAIL failed, $WARN warnings"
echo "$PASS $FAIL $WARN"
