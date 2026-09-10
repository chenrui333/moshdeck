#!/usr/bin/env python3
"""Build the pinned iOS Ghostty package without gettext. Run on an Apple Silicon Mac."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess

WRAPPER = "733ae3b29d447b6707cbfc00879027a076dfd0eb"
CORE = "c4e16970a803b170e352432424f44192cb59f3ac"
ROOT = Path(__file__).resolve().parents[2]


def run(*args, cwd=None, env=None):
    subprocess.run(args, cwd=cwd, env=env, check=True)


def checkout(url, revision, destination):
    run("git", "init", str(destination))
    run("git", "-C", str(destination), "remote", "add", "origin", url)
    run("git", "-C", str(destination), "fetch", "--depth=1", "origin", revision)
    run("git", "-C", str(destination), "checkout", "--detach", "FETCH_HEAD")
    actual = subprocess.check_output(["git", "-C", str(destination), "rev-parse", "HEAD"], text=True).strip()
    if actual != revision:
        raise RuntimeError("Dependency revision mismatch")


def main():
    import os
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".build/ghostty-ios")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("Requires an Apple Silicon Mac; builds arm64 iOS and arm64 Simulator")
    zig = subprocess.check_output(["zig", "version"], text=True).strip()
    if zig != "0.16.0":
        parser.error("This recipe is qualified with Zig 0.16.0")
    output = args.output.resolve()
    # Never delete or reset an existing checkout. A failed run remains inspectable.
    if output.exists():
        parser.error("Output already exists; use a new --output directory")
    output.mkdir(parents=True)
    wrapper, source = output / "wrapper", output / "source"
    checkout("https://github.com/Lakr233/libghostty-spm.git", WRAPPER, wrapper)
    checkout("https://github.com/ghostty-org/ghostty.git", CORE, source)
    env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(output / "cache/zig-global"),
               BUILD_CACHE_ROOT=str(output / "cache"), ZIG_BUILD_EXTRA_ARGS="-Di18n=false")
    run(str(wrapper / "Script/apply-patches.sh"), str(source), cwd=wrapper, env=env)
    patch = ROOT / "Spike/patches/ghostty-conditional-libintl.patch"
    run("git", "-C", str(source), "apply", "--check", str(patch))
    run("git", "-C", str(source), "apply", str(patch))
    artifacts = []
    for target, name in [("aarch64-ios", "device"), ("aarch64-ios-simulator", "simulator")]:
        destination = output / name
        run(str(wrapper / "Script/build-ghostty.sh"), str(source), target, str(destination), cwd=wrapper, env=env)
        library = destination / "lib/libghostty.a"
        symbols = subprocess.check_output(["nm", "-g", str(library)], text=True)
        if not symbols.strip() or any(term in symbols for term in
                                    ["libintl", "bindtextdomain", "dgettext", "textdomain", "_libgettext"]):
            raise RuntimeError("Candidate archive symbol audit failed")
        artifacts.append({"target": target, "bytes": library.stat().st_size,
                          "sha256": hashlib.sha256(library.read_bytes()).hexdigest()})
    package = output / "package"
    package.mkdir()
    shutil.copytree(wrapper / "Sources", package / "Sources")
    shutil.copy2(wrapper / "LICENSE", package / "LICENSE")
    manifest = (wrapper / "Package.local.swift").read_text()
    manifest = manifest.replace('from: "2.2.0"', 'exact: "2.2.0"')
    (package / "Package.swift").write_text(manifest)
    run("xcodebuild", "-create-xcframework",
        "-library", str(output / "device/lib/libghostty.a"), "-headers", str(output / "device/include"),
        "-library", str(output / "simulator/lib/libghostty.a"), "-headers", str(output / "simulator/include"),
        "-output", str(package / "BinaryTarget/GhosttyKit.xcframework"))
    provenance = {"wrapper": WRAPPER, "core": CORE, "zig": zig, "i18n": False,
                  "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
                  "patchSHA256": hashlib.sha256(patch.read_bytes()).hexdigest(), "artifacts": artifacts}
    (package / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Prepared local Swift package: {package}")


if __name__ == "__main__":
    main()
