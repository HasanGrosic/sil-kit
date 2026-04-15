# SPDX-FileCopyrightText: 2026 Vector Informatik GmbH
#
# SPDX-License-Identifier: MIT
#
# BUILD file for the QNX SDP local repository.
# Derived from the QNX 8.0 SDP Bazel toolchain (BlackBerry / Apache-2.0).

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_files",
    srcs = glob(["*/**/*"]),
)

# Built-in include directories for the QNX C++ toolchain.
filegroup(
    name = "cxx_builtin_include_directories",
    srcs = [
        "host/linux/x86_64/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0/include",
        "target/qnx/usr/include",
        "target/qnx/usr/include/c++/v1",
    ],
)

# ---------------------------------------------------------------------------
# Common tools (architecture-independent)
# ---------------------------------------------------------------------------
filegroup(
    name = "qcc",
    srcs = ["host/linux/x86_64/usr/bin/qcc"],
)

filegroup(
    name = "qpp",
    srcs = ["host/linux/x86_64/usr/bin/q++"],
)

filegroup(
    name = "usemsg",
    srcs = ["host/linux/x86_64/usr/bin/usemsg"],
)

# ---------------------------------------------------------------------------
# Architecture-specific tools
# ---------------------------------------------------------------------------

# x86_64
filegroup(
    name = "ar_x86_64",
    srcs = ["host/linux/x86_64/usr/bin/x86_64-pc-nto-qnx8.0.0-ar"],
)

filegroup(
    name = "strip_x86_64",
    srcs = ["host/linux/x86_64/usr/bin/x86_64-pc-nto-qnx8.0.0-strip"],
)

# aarch64
filegroup(
    name = "ar_aarch64",
    srcs = ["host/linux/x86_64/usr/bin/aarch64-unknown-nto-qnx8.0.0-ar"],
)

filegroup(
    name = "strip_aarch64",
    srcs = ["host/linux/x86_64/usr/bin/aarch64-unknown-nto-qnx8.0.0-strip"],
)

# ---------------------------------------------------------------------------
# Target / Host directory markers (used by cc_toolchain_config for QNX_TARGET)
# ---------------------------------------------------------------------------
filegroup(
    name = "target_dir",
    srcs = ["target/qnx"],
)

filegroup(
    name = "host_dir",
    srcs = ["host"],
)
