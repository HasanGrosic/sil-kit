#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Vector Informatik GmbH
#
# SPDX-License-Identifier: MIT

# Workspace status command for the SIL Kit Bazel build.
# Outputs key-value pairs consumed by stamped genrules (version_macros.hpp).
#
# Keys prefixed with STABLE_ cause full rebuilds when their values change.
# See: https://bazel.build/docs/user-manual#workspace-status

# .git may be a directory (normal checkout) or a file (worktree / submodule).
if [ -e ".git" ]; then
    echo "STABLE_GIT_HASH $(git rev-parse HEAD 2>/dev/null || echo unknown)"
else
    echo "STABLE_GIT_HASH unknown"
fi
