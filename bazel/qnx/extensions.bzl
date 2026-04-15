# SPDX-FileCopyrightText: 2026 Vector Informatik GmbH
#
# SPDX-License-Identifier: MIT

"""Module extension for QNX cross-compilation toolchains.

Creates two external repositories:
  - @qnx_sdp         – points to the installed QNX SDP root
  - @qnx_cc_toolchain – provides constraint_setting/constraint_value, platforms,
                         cc_toolchain definitions, and toolchain() registrations

When QNX_HOST is **not** set in the environment the extension creates lightweight
stubs that still expose the QNX constraint and platform definitions (so that
config_setting / select works everywhere) but do not register functional
toolchains.  Attempting ``--config=qnx_x86_64`` without QNX_HOST will produce a
clear "no matching toolchain" error.
"""

load("@bazel_tools//tools/build_defs/repo:local.bzl", "new_local_repository")

# ============================================================================
# SDP repository BUILD content
# ============================================================================
# Inline so we avoid label-resolution issues when new_local_repository tries
# to load a build_file from the root module inside a module extension context.

_SDP_BUILD_CONTENT = """\
# BUILD file for the QNX SDP local repository.
# Derived from the QNX 8.0 SDP Bazel toolchain (BlackBerry / Apache-2.0).
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_files",
    srcs = glob(["*/**/*"]),
)

filegroup(
    name = "cxx_builtin_include_directories",
    srcs = [
        "host/linux/x86_64/usr/lib/gcc/x86_64-pc-nto-qnx8.0.0/12.2.0/include",
        "target/qnx/usr/include",
        "target/qnx/usr/include/c++/v1",
    ],
)

filegroup(name = "qcc",  srcs = ["host/linux/x86_64/usr/bin/qcc"])
filegroup(name = "qpp",  srcs = ["host/linux/x86_64/usr/bin/q++"])
filegroup(name = "usemsg", srcs = ["host/linux/x86_64/usr/bin/usemsg"])

filegroup(name = "ar_x86_64",    srcs = ["host/linux/x86_64/usr/bin/x86_64-pc-nto-qnx8.0.0-ar"])
filegroup(name = "strip_x86_64", srcs = ["host/linux/x86_64/usr/bin/x86_64-pc-nto-qnx8.0.0-strip"])

filegroup(name = "ar_aarch64",    srcs = ["host/linux/x86_64/usr/bin/aarch64-unknown-nto-qnx8.0.0-ar"])
filegroup(name = "strip_aarch64", srcs = ["host/linux/x86_64/usr/bin/aarch64-unknown-nto-qnx8.0.0-strip"])

filegroup(name = "target_dir", srcs = ["target/qnx"])
filegroup(name = "host_dir",   srcs = ["host"])
"""

# ============================================================================
# Stub repository (no QNX SDP available)
# ============================================================================

_STUB_SDP_BUILD = """\
# Stub – QNX SDP is not available on this host.
package(default_visibility = ["//visibility:public"])
"""

_STUB_TOOLCHAIN_BUILD = """\
# Stub – QNX SDP is not available on this host.
# Constraint and platform definitions are provided so that config_setting and
# select() work on any host.  Functional toolchains require QNX_HOST to be set.
package(default_visibility = ["//visibility:public"])

constraint_setting(name = "os")
constraint_value(
    name = "qnx",
    constraint_setting = ":os",
)

platform(
    name = "qnx_x86_64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        ":qnx",
    ],
)

platform(
    name = "qnx_aarch64le",
    constraint_values = [
        "@platforms//cpu:aarch64",
        "@platforms//os:linux",
        ":qnx",
    ],
)
"""

def _stub_repo_impl(repo_ctx):
    repo_ctx.file("BUILD.bazel", repo_ctx.attr.build_content)

_stub_repo = repository_rule(
    implementation = _stub_repo_impl,
    attrs = {"build_content": attr.string()},
)

# ============================================================================
# Real QNX toolchain repository rule
# ============================================================================

# BUILD content for the toolchain repo when the SDP is available.
_TOOLCHAIN_BUILD = """\
package(default_visibility = ["//visibility:public"])
load(":cc_toolchain_config.bzl", "cc_toolchain_config_qnx")

# ---------------------------------------------------------------------------
# QNX constraint (custom, not @platforms//os:qnx)
# ---------------------------------------------------------------------------
constraint_setting(name = "os")
constraint_value(
    name = "qnx",
    constraint_setting = ":os",
)

# ---------------------------------------------------------------------------
# QNX platform definitions
# ---------------------------------------------------------------------------
platform(
    name = "qnx_x86_64",
    constraint_values = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
        ":qnx",
    ],
)

platform(
    name = "qnx_aarch64le",
    constraint_values = [
        "@platforms//cpu:aarch64",
        "@platforms//os:linux",
        ":qnx",
    ],
)

# ---------------------------------------------------------------------------
# Tool filegroups
# ---------------------------------------------------------------------------
filegroup(
    name = "all_files",
    srcs = ["@qnx_sdp//:all_files"],
)

filegroup(name = "empty")

# ===========================================================================
# x86_64 cc toolchain
# ===========================================================================
cc_toolchain_config_qnx(
    name = "qcc_toolchain_config_x86_64",
    arch = "x86_64",
    cc_binary = "@qnx_sdp//:qcc",
    cxx_binary = "@qnx_sdp//:qpp",
    qnx_target = "@qnx_sdp//:target_dir",
    qnx_host = "@qnx_sdp//:host_dir",
    ar_binary = "@qnx_sdp//:ar_x86_64",
    strip_binary = "@qnx_sdp//:strip_x86_64",
    usemsg_binary = "@qnx_sdp//:usemsg",
    stage_path = "",
    cxx_builtin_include_directories = "@qnx_sdp//:cxx_builtin_include_directories",
)

cc_toolchain(
    name = "qcc_toolchain_x86_64",
    all_files = ":all_files",
    ar_files = ":all_files",
    as_files = ":all_files",
    compiler_files = ":all_files",
    dwp_files = ":empty",
    linker_files = ":all_files",
    objcopy_files = ":empty",
    strip_files = ":all_files",
    toolchain_config = ":qcc_toolchain_config_x86_64",
)

toolchain(
    name = "qcc_x86_64",
    exec_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        ":qnx",
    ],
    toolchain = ":qcc_toolchain_x86_64",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

# ===========================================================================
# aarch64le cc toolchain
# ===========================================================================
cc_toolchain_config_qnx(
    name = "qcc_toolchain_config_aarch64le",
    arch = "aarch64le",
    cc_binary = "@qnx_sdp//:qcc",
    cxx_binary = "@qnx_sdp//:qpp",
    qnx_target = "@qnx_sdp//:target_dir",
    qnx_host = "@qnx_sdp//:host_dir",
    ar_binary = "@qnx_sdp//:ar_aarch64",
    strip_binary = "@qnx_sdp//:strip_aarch64",
    usemsg_binary = "@qnx_sdp//:usemsg",
    stage_path = "",
    cxx_builtin_include_directories = "@qnx_sdp//:cxx_builtin_include_directories",
)

cc_toolchain(
    name = "qcc_toolchain_aarch64le",
    all_files = ":all_files",
    ar_files = ":all_files",
    as_files = ":all_files",
    compiler_files = ":all_files",
    dwp_files = ":empty",
    linker_files = ":all_files",
    objcopy_files = ":empty",
    strip_files = ":all_files",
    toolchain_config = ":qcc_toolchain_config_aarch64le",
)

toolchain(
    name = "qcc_aarch64le",
    exec_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    target_compatible_with = [
        "@platforms//cpu:aarch64",
        ":qnx",
    ],
    toolchain = ":qcc_toolchain_aarch64le",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)
"""

def _qnx_toolchain_repo_impl(repo_ctx):
    """Repository rule that generates the QNX CC toolchain repo."""
    sdp_root = repo_ctx.attr.sdp_root

    # Copy cc_toolchain_config.bzl from the installed SDP
    config_bzl = sdp_root + "/host/common/fsp/bazel_toolchain/qnx_toolchain/cc_toolchain_config.bzl"
    repo_ctx.symlink(config_bzl, "cc_toolchain_config.bzl")

    # Write the BUILD file
    repo_ctx.file("BUILD.bazel", _TOOLCHAIN_BUILD)

_qnx_toolchain_repo = repository_rule(
    implementation = _qnx_toolchain_repo_impl,
    local = True,
    attrs = {
        "sdp_root": attr.string(mandatory = True),
    },
)

# ============================================================================
# Module extension entry-point
# ============================================================================

def _qnx_toolchain_extension_impl(mod_ctx):
    qnx_host = mod_ctx.os.environ.get("QNX_HOST", "")

    if qnx_host:
        # Derive SDP root: QNX_HOST is typically <sdp>/host/linux/x86_64
        sdp_root = qnx_host + "/../../.."

        # SDP local repository (provides tool filegroups)
        new_local_repository(
            name = "qnx_sdp",
            path = sdp_root,
            build_file_content = _SDP_BUILD_CONTENT,
        )

        # Toolchain repository (constraint + platform + cc_toolchain)
        _qnx_toolchain_repo(
            name = "qnx_cc_toolchain",
            sdp_root = sdp_root,
        )
    else:
        # No QNX SDP – create stubs so constraint/platform labels resolve.
        _stub_repo(
            name = "qnx_sdp",
            build_content = _STUB_SDP_BUILD,
        )
        _stub_repo(
            name = "qnx_cc_toolchain",
            build_content = _STUB_TOOLCHAIN_BUILD,
        )

qnx_toolchain_ext = module_extension(
    implementation = _qnx_toolchain_extension_impl,
    environ = ["QNX_HOST"],
)
