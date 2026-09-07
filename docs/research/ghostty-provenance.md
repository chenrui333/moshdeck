# Ghostty dependency reproduction

Checkpoint September 7, 2026. The shipping spike still uses the previously verified pinned artifact. An isolated source rebuild is being qualified; no dependency swap has been made.

## Exact inputs and artifact identity

- Swift wrapper release: 1.5.20260906, revision `733ae3b29d447b6707cbfc00879027a076dfd0eb` in Lakr233/libghostty-spm.
- Core: `c4e16970a803b170e352432424f44192cb59f3ac` in ghostty-org/ghostty, from that wrapper's Ghostty.ref.
- Storage release: `upstream.c4e16970a803`; manifest artifact is GhosttyKit.xcframework.zip.
- Expected SHA-256: `bd9bba3b95652900e87a6a0f190f33d82a1d8e42d1c0119c330072be361385da`.
- On September 7, the cached SwiftPM archive was hashed independently and matched exactly. A fresh GitHub HTTPS download timed out; verification used the actual cached archive, not only the manifest string. Identity does not establish publisher trust or a complete binary/source correspondence.
- Toolchain for the local reproduction attempt: Zig 0.16.0, Xcode 26.6 (17F113), Apple Silicon Mac. Pinned workflow also selects Zig 0.16.0.
- [Build input manifest](ghostty-build-inputs.json) records hashes of the wrapper manifests, patch files and top-level pipeline scripts. Transitive Zig dependencies are additionally defined by the pinned core and its package manifests; this is not yet a complete SBOM.

## Reproduction procedure

Use a disposable directory; do not run patch/build scripts inside SwiftPM's active checkout. The build script deletes its own generated output directories.

```sh
rebuild_dir=$(mktemp -d -t moshdeck-ghostty-rebuild)
git clone https://github.com/Lakr233/libghostty-spm.git "$rebuild_dir/wrapper"
git -C "$rebuild_dir/wrapper" checkout --detach 733ae3b29d447b6707cbfc00879027a076dfd0eb
git clone https://github.com/ghostty-org/ghostty.git "$rebuild_dir/core"
git -C "$rebuild_dir/core" checkout --detach c4e16970a803b170e352432424f44192cb59f3ac
zig version
xcodebuild -version
xcodebuild -downloadComponent MetalToolchain
cd "$rebuild_dir/wrapper"
./Script/check-licenses.sh
./build.sh --source "$rebuild_dir/core" --platforms ios --skip-tests
```

Require Zig 0.16.0 and record the Xcode/SDK version. An existing source directory must already be at the specified core revision: the build's default pin logic applies only when it clones missing source. The ios platform group builds arm64 iPhone plus arm64/x86_64 simulators, assembling BinaryTarget/GhosttyKit.xcframework and build/GhosttyKit.xcframework.zip. `--skip-tests` skips the wrapper's broad platform test suite; it does not constitute app validation.

After successful reproduction, use Package.local.swift in that isolated wrapper to consume the local artifact. Resolve/pin the same MSDisplayLink revision as the app's Package.resolved, inspect the generated slices/headers/notices, and qualify an app build against this local package in an isolated project copy. Do not replace the app dependency until physical rendering/input/SSH regressions pass. A local iOS-only zip is not expected to match a multi-platform release archive byte-for-byte; record its own checksum and toolchain instead of changing the expected release checksum.

## Patch scope

The pinned patch directory and its README describe variants selected by upstream API markers. The local attempt applied the modern-v2 host-managed I/O path. Major patch areas:

- Darwin static-library/header installation and custom stream I/O callbacks.
- iOS build enablement, CoreText/IOSurface/Metal behavior and row alignment.
- Prebuilt frame data, disabled custom shaders, inspector and unused desktop components.
- Private desktop blur API removal; libc++ availability and archive-tool fixes.
- Scroll remainder correctness and terminal-response suppression for replay APIs.
- Catalyst/visionOS target compatibility and Zig-package target fixes, even though this reproduction selects only the iOS group.

The source build logs record actual applied versus skipped variants. This is an upstream fork/patch maintenance dependency, not an official unmodified Ghostty iOS API. MoshDeck does not replay saved terminal transcripts, and still denies remote clipboard operations independently of the fork's replay suppression.

## Current empirical result

The isolated exact revisions were checked out, wrapper license-resource check passed, dependencies fetched, and patches applied. The first arm64 iOS build failed at the Metal shader compiler because Xcode's optional Metal Toolchain was missing. There were no other reported compiler failures in that run. The Apple Metal Toolchain 17F109 subsequently installed successfully, verified by xcodebuild component status. The same isolated source build was restarted and is compiling the arm64 iPhone target. No self-built XCFramework or app using it has passed yet.

The wrapper license check confirms its tracked-resource policy, not all native static-library licenses. Original MIT wrapper/core notices, the MIT shell-integration rewrites and vendored bash-preexec notice must accompany distribution as applicable. Complete native/font/transitive notices and link/resource audit remain pending; see [license review](licenses.md).

## Upgrade contract

Change wrapper/core/artifact pins together only after reviewing the exact upstream diff, chosen patch variants, resource/license changes and minimum toolchain. Independently verify the new artifact hash, rerun source reproduction, compare headers/slices/resources, and run core plus physical terminal/clipboard/keyboard/resize/reconnect checks. Keep the previous working pin recoverable. Never accept a checksum mismatch, floating version, silent patch failure or trust-all transport workaround.
