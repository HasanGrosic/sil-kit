# SPDX-FileCopyrightText: 2026 Vector Informatik GmbH
#
# SPDX-License-Identifier: MIT

"""Common Bazel macros for the SIL Kit build.

Provides helper functions that mirror common CMake patterns used across SilKit.
"""

load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

def silkit_cc_library(
        name,
        copts = [],
        local_defines = [],
        linkopts = [],
        **kwargs):
    """A cc_library wrapper that applies SIL Kit default settings.

    Applies hidden visibility and position-independent code to all SilKit
    libraries, matching the CMake defaults.

    Args:
        name: Target name.
        copts: Additional compiler options.
        local_defines: Additional local defines.
        linkopts: Additional linker options.
        **kwargs: Passed through to cc_library.
    """
    cc_library(
        name = name,
        copts = copts,
        local_defines = local_defines,
        linkopts = linkopts,
        **kwargs
    )

def silkit_data_test(
        name,
        srcs,
        deps = [],
        data_files = [],
        subdir_data = {},
        size = "small",
        timeout = None,
        tags = [],
        defines = [],
        copts = [],
        local_defines = [],
        **kwargs):
    """A test wrapper that makes data files available flat in the test CWD.

    Some SIL Kit tests open config files by bare filename from the current
    working directory.  Bazel's data attribute places files under a runfiles
    subtree that mirrors the source layout, which does not match the flat
    layout expected by these tests.

    This macro creates a cc_binary for the test and wraps it with an sh_test
    that symlinks data files flat into a temporary directory before executing
    the binary.

    Args:
        name: Test target name.
        srcs: C++ source files for the test.
        deps: cc_library dependencies.
        data_files: Labels of files to symlink flat into the test CWD.
        subdir_data: Dict mapping subdirectory names to lists of file labels.
            Files are placed under <subdir>/<basename> in the test CWD.
        size: Test size (default "small").
        timeout: Test timeout.
        tags: Test tags.
        defines: Compile definitions.
        copts: Compiler options.
        local_defines: Local compile definitions.
        **kwargs: Extra attrs forwarded to cc_binary.
    """
    bin_name = name + "_bin"

    cc_binary(
        name = bin_name,
        testonly = True,
        srcs = srcs,
        deps = deps,
        defines = defines,
        copts = copts,
        local_defines = local_defines,
        linkstatic = True,
        **kwargs
    )

    # Build the sh_test args list: binary, then flat files, then subdir files
    args = ["$(rootpath :{})".format(bin_name)]
    all_data = [":" + bin_name] + list(data_files)

    for f in data_files:
        args.append("$(rootpath {})".format(f))

    for subdir, files in subdir_data.items():
        args.append("--subdir={}".format(subdir))
        for f in files:
            args.append("$(rootpath {})".format(f))
            if f not in all_data:
                all_data.append(f)

    sh_test_kwargs = {"size": size, "tags": tags}
    if timeout:
        sh_test_kwargs["timeout"] = timeout

    native.sh_test(
        name = name,
        srcs = ["//bazel:run_with_data.sh"],
        data = all_data,
        args = args,
        **sh_test_kwargs
    )
