"""Load Dawn from a prebuilt webgpu_dawn.dll (webnn route-A WebGPU, Windows port).

Replaces the upstream http_archive, which fetches Dawn *source* and generates only
headers. That suffices on Linux, where the produced .so may carry undefined wgpu*
symbols to be bound at load time, but a Windows DLL must resolve every symbol at
link time -- linking against headers alone leaves ~20 undefined wgpu* symbols plus
dawnProcSetProcs (because @dawn//:libdawn_proc in dawn.BUILD is headers-only).

So point @dawn at a prebuilt tree produced by scripts/build_dawn.ps1 and link its
import lib. Override the location with the DAWN_PREBUILT_DIR env var, which
scripts/build_accelerator_dll.ps1 sets from its -DawnDir parameter.

IMPORTANT: the prebuilt tree must be built from the Dawn version THIS litert
revision pins in the upstream version of this file -- not the Dawn inside Chrome.
ml_drift links its own Dawn Native, so Chrome's version is irrelevant. Building a
mismatched Dawn produces confusing compile errors (e.g. "no member named
'loadDataFunction'") and degrades pooling results. See LOCAL-CHANGES.md.

  litert aea19e7fe pins: v20260720.160313

Exposes @dawn//:{webgpu_dawn,webgpu_headers,dawn_headers,libdawn_proc}
and the @dawn//dawn: package aliases.
"""

_WIN_ROOT_BUILD = """
cc_import(
    name = "dawn_import",
    interface_library = "lib/webgpu_dawn.lib",
    shared_library = "lib/webgpu_dawn.dll",
    visibility = ["//visibility:public"],
)

cc_library(
    name = "libdawn",
    hdrs = glob(["include/**/*.h*"]),
    includes = ["include"],
    deps = [":dawn_import"],
    visibility = ["//visibility:public"],
)

alias(name = "webgpu_dawn",    actual = ":libdawn", visibility = ["//visibility:public"])
alias(name = "webgpu_headers", actual = ":libdawn", visibility = ["//visibility:public"])
alias(name = "dawn_headers",   actual = ":libdawn", visibility = ["//visibility:public"])
# Only referenced from the ml_drift_use_dawn_proc select() branch, which this
# configuration does not take. Aliased so the label still resolves.
alias(name = "libdawn_proc",   actual = ":libdawn", visibility = ["//visibility:public"])
"""

_POSIX_ROOT_BUILD = """
cc_library(
    name = "libdawn",
    hdrs = glob(["include/**/*.h*"]),
    includes = ["include"],
    srcs = glob(["lib/libdawn.*"]),
    visibility = ["//visibility:public"],
)

alias(name = "webgpu_dawn",    actual = ":libdawn", visibility = ["//visibility:public"])
alias(name = "webgpu_headers", actual = ":libdawn", visibility = ["//visibility:public"])
alias(name = "dawn_headers",   actual = ":libdawn", visibility = ["//visibility:public"])
alias(name = "libdawn_proc",   actual = ":libdawn", visibility = ["//visibility:public"])
"""

_DAWN_PKG_BUILD = """
alias(name = "webgpu_dawn",  actual = "@dawn//:libdawn", visibility = ["//visibility:public"])
alias(name = "dawn_headers", actual = "@dawn//:libdawn", visibility = ["//visibility:public"])
"""

def _prebuilt_dawn_impl(ctx):
    is_win = ctx.os.name.startswith("windows")
    default_dir = "E:\\webnn-build\\_dawn_prebuilt_win_20260720" if is_win else "/tmp/dawn/webgpu-dawn-binaries/out/latest"
    path = ctx.os.environ.get("DAWN_PREBUILT_DIR", default_dir)

    for d in ["include", "lib"]:
        ctx.execute(["cmd", "/c", "mkdir", d] if is_win else ["mkdir", "-p", d], quiet = True)
        if is_win:
            # xcopy /E /I /Y /Q: recursive, treat dest as dir, overwrite, quiet
            src = path.rstrip("\\") + "\\" + d
            res = ctx.execute(["cmd", "/c", "xcopy", "/E", "/I", "/Y", "/Q", src, d])
        else:
            res = ctx.execute(["bash", "-c", "cp -RL %s/%s/. %s/" % (path, d, d)])
        if res.return_code != 0:
            fail("prebuilt_dawn: copy '%s' from '%s' failed: %s" % (d, path, res.stderr))

    ctx.file("BUILD", _WIN_ROOT_BUILD if is_win else _POSIX_ROOT_BUILD)
    ctx.file("dawn/BUILD", _DAWN_PKG_BUILD)

prebuilt_dawn = repository_rule(
    implementation = _prebuilt_dawn_impl,
    environ = ["DAWN_PREBUILT_DIR"],
    local = True,
)

def repo():
    prebuilt_dawn(name = "dawn")
