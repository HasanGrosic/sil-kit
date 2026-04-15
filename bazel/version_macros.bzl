# SPDX-FileCopyrightText: 2026 Vector Informatik GmbH
#
# SPDX-License-Identifier: MIT

"""Custom rule to generate version_macros.hpp with git-hash stamping.

Uses ctx.info_file (stable workspace status) to read STABLE_GIT_HASH,
which is written by bazel/print_workspace_status.sh.
"""

def _version_macros_impl(ctx):
    template = ctx.file.template
    output = ctx.outputs.out
    stable_status = ctx.info_file

    ctx.actions.run_shell(
        inputs = [template, stable_status],
        outputs = [output],
        command = """
            GIT_HASH=$(grep 'STABLE_GIT_HASH ' {status} | cut -d' ' -f2- || echo 'unknown')
            sed \
                -e "s/@GIT_HEAD_HASH@/$GIT_HASH/" \
                -e 's/@PROJECT_VERSION_MAJOR@/{major}/' \
                -e 's/@PROJECT_VERSION_MINOR@/{minor}/' \
                -e 's/@PROJECT_VERSION_PATCH@/{patch}/' \
                -e 's/@SILKIT_BUILD_NUMBER@/{build_number}/' \
                -e 's/@PROJECT_VERSION@/{version}/' \
                -e 's/@SILKIT_VERSION_SUFFIX@/{suffix}/' \
                {template} > {output}
        """.format(
            status = stable_status.path,
            template = template.path,
            output = output.path,
            major = ctx.attr.version_major,
            minor = ctx.attr.version_minor,
            patch = ctx.attr.version_patch,
            build_number = ctx.attr.build_number,
            version = ctx.attr.version_string,
            suffix = ctx.attr.version_suffix,
        ),
    )

    return [DefaultInfo(files = depset([output]))]

version_macros = rule(
    implementation = _version_macros_impl,
    attrs = {
        "template": attr.label(
            allow_single_file = [".in"],
            mandatory = True,
            doc = "The version_macros.hpp.in template file.",
        ),
        "out": attr.output(
            mandatory = True,
            doc = "The generated version_macros.hpp output file.",
        ),
        "version_major": attr.string(default = "5"),
        "version_minor": attr.string(default = "0"),
        "version_patch": attr.string(default = "5"),
        "build_number": attr.string(default = "0"),
        "version_string": attr.string(default = "5.0.5"),
        "version_suffix": attr.string(default = ""),
    },
    doc = "Generates version_macros.hpp from the .in template, stamped with the git hash.",
)
