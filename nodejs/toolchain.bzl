# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""This module implements the node toolchain rule.
"""

NodeInfo = provider(
    doc = "Information about how to invoke the node executable.",
    fields = {
        "target_tool_path": "Path to the nodejs executable for this target's platform.",
        "tool_files": """Files required in runfiles to make the nodejs executable available.

May be empty if the target_tool_path points to a locally installed node binary.""",
        "npm_path": "Path to the npm executable for this target's platform.",
        "npm_files": """Files required in runfiles to make the npm executable available.

May be empty if the npm_path points to a locally installed npm binary.""",
        "run_npm": """A template for a script that wraps npm.
        On Windows, this is a Batch script, otherwise it uses Bash.""",
        "headers": """\
(struct) Information about the header files, with fields:
  * providers_map: a dict of string to provider instances. The key should be
    a fully qualified name (e.g. `@rules_foo//bar:baz.bzl#MyInfo`) of the
    provider to uniquely identify its type.

    The following keys are always present:
      * CcInfo: the CcInfo provider instance for the headers.
      * DefaultInfo: the DefaultInfo provider instance for the headers.

    A map is used to allow additional providers from the originating headers
    target (typically a `cc_library`) to be propagated to consumers (directly
    exposing a Target object can cause memory issues and is an anti-pattern).

    When consuming this map, it's suggested to use `providers_map.values()` to
    return all providers; or copy the map and filter out or replace keys as
    appropriate. Note that any keys begining with `_` (underscore) are
    considered private and should be forward along as-is (this better allows
    e.g. `:current_node_cc_headers` to act as the underlying headers target it
    represents).
""",
    },
)

# Avoid using non-normalized paths (workspace/../other_workspace/path)
def _to_manifest_path(ctx, file):
    if file.short_path.startswith("../"):
        return "external/" + file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def _node_toolchain_impl(ctx):
    if ctx.attr.target_tool and ctx.attr.target_tool_path:
        fail("Can only set one of target_tool or target_tool_path but both were set.")
    if not ctx.attr.target_tool and not ctx.attr.target_tool_path:
        fail("Must set one of target_tool or target_tool_path.")
    if ctx.attr.npm and ctx.attr.npm_path:
        fail("Can only set one of npm or npm_path but both were set.")

    tool_files = []
    target_tool_path = ctx.attr.target_tool_path

    if ctx.attr.target_tool:
        tool_files = [ctx.file.target_tool]
        target_tool_path = _to_manifest_path(ctx, ctx.file.target_tool)

    npm_files = []
    npm_path = ctx.attr.npm_path

    if ctx.attr.npm:
        npm_files = depset([ctx.file.npm] + ctx.files.npm_files).to_list()
        npm_path = _to_manifest_path(ctx, ctx.file.npm)

    # Make the $(NODE_PATH) variable available in places like genrules.
    # See https://docs.bazel.build/versions/main/be/make-variables.html#custom_variables
    template_variables = platform_common.TemplateVariableInfo({
        "NODE_PATH": target_tool_path,
        "NPM_PATH": npm_path,
    })
    default = DefaultInfo(
        files = depset(tool_files),
        runfiles = ctx.runfiles(files = tool_files),
    )
    nodeinfo = NodeInfo(
        target_tool_path = target_tool_path,
        tool_files = tool_files,
        npm_path = npm_path,
        npm_files = npm_files,
        run_npm = ctx.file.run_npm,
        headers = struct(
            providers_map = {
                "CcInfo": ctx.attr.headers[CcInfo],
                "DefaultInfo": ctx.attr.headers[DefaultInfo],
            },
        ),
    )

    # Export all the providers inside our ToolchainInfo
    # so the resolved_toolchain rule can grab and re-export them.
    toolchain_info = platform_common.ToolchainInfo(
        nodeinfo = nodeinfo,
        template_variables = template_variables,
        default = default,
    )
    return [
        default,
        toolchain_info,
        template_variables,
    ]

node_toolchain = rule(
    implementation = _node_toolchain_impl,
    attrs = {
        "target_tool": attr.label(
            doc = "A hermetically downloaded nodejs executable target for this target's platform.",
            mandatory = False,
            allow_single_file = True,
        ),
        "target_tool_path": attr.string(
            doc = "Path to an existing nodejs executable for this target's platform.",
            mandatory = False,
        ),
        "npm": attr.label(
            doc = "A hermetically downloaded npm executable target for this target's platform.",
            mandatory = False,
            allow_single_file = True,
        ),
        "npm_path": attr.string(
            doc = "Path to an existing npm executable for this target's platform.",
            mandatory = False,
        ),
        "npm_files": attr.label_list(
            doc = "Files required in runfiles to run npm.",
            mandatory = False,
        ),
        "run_npm": attr.label(
            doc = "A template file that allows us to execute npm",
            allow_single_file = True,
        ),
        "headers": attr.label(
            doc = "A cc_library that contains the Node/v8 header files for this target platform.",
        ),
    },
    doc = """Defines a node toolchain for a platform.

You can use this to refer to a vendored nodejs binary in your repository,
or even to compile nodejs from sources using rules_foreign_cc or other rules.

First, in a BUILD.bazel file, create a node_toolchain definition:

```starlark
load("@rules_nodejs//nodejs:toolchain.bzl", "node_toolchain")

node_toolchain(
    name = "node_toolchain",
    target_tool = "//some/path/bin/node",
)
```

Next, declare which execution platforms or target platforms the toolchain should be selected for
based on constraints.

```starlark
toolchain(
    name = "my_nodejs",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    toolchain = ":node_toolchain",
    toolchain_type = "@rules_nodejs//nodejs:toolchain_type",
)
```

See https://bazel.build/extending/toolchains#toolchain-resolution for more information on toolchain
resolution.

Finally in your `WORKSPACE`, register it with `register_toolchains("//:my_nodejs")`

For usage see https://docs.bazel.build/versions/main/toolchains.html#defining-toolchains.
You can use the `--toolchain_resolution_debug` flag to `bazel` to help diagnose which toolchain is selected.
""",
)
