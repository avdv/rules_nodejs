"Fetches needed to run the typescript compiler"

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def ts_repositories(
        # If you override the name, you'll also have to override the `tsc` attr of ts_project
        name = "typescript",
        # TODO: provide an easy way to ensure this version matches the one in package.json
        ts_version = "4.3.5",
        sha256 = "c7be550da858be7abfc73dd0b9060ab23ce835ae3b05931f4500a25c09766d45"):
    http_archive(
        name = name,
        build_file_content = """# Generated by /ts/repositories.bzl
load("@build_bazel_rules_nodejs//:index.bzl", "nodejs_binary")
load("@rules_nodejs//third_party/github.com/bazelbuild/bazel-skylib:rules/copy_file.bzl", "copy_file")
load("@bazel_skylib//rules:write_file.bzl", "write_file")

# Turn a source directory into a TreeArtifact for RBE-compat
copy_file(
    name = "npm_typescript-{0}",
    src = "package",
    # This attribute comes from rules_nodejs patch of
    # https://github.com/bazelbuild/bazel-skylib/pull/323
    is_directory = True,
    # We must give this as the directory in order for it to appear on NODE_PATH
    out = "package",
    visibility = ["//visibility:public"],
)

write_file(
    name = "gen_tsc.js",
    out = "tsc.js",
    content = [
        "const runfiles = require(process.env['BAZEL_NODE_RUNFILES_HELPER'])",
        "require(runfiles.resolve('npm_typescript-{0}') + '/package/bin/tsc')",
    ],
)

nodejs_binary(
    name = "tsc",
    data = ["@npm_typescript-{0}"],
    entry_point = "tsc.js",
    visibility = ["//visibility:public"],
)
""".format(ts_version),
        sha256 = "",
        urls = ["https://registry.npmjs.org/typescript/-/typescript-%s.tgz" % ts_version],
    )
