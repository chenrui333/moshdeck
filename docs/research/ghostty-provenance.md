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

The isolated exact revisions were checked out, wrapper license-resource check passed, dependencies fetched, and patches applied. The first arm64 iOS build failed at the Metal shader compiler because Xcode's optional Metal Toolchain was missing. There were no other reported compiler failures in that run. The Apple Metal Toolchain 17F109 subsequently installed successfully, verified by xcodebuild component status. The same isolated source build then completed successfully for arm64 iPhone plus arm64/x86_64 simulator. The wrapper verified the assembled XCFramework layout and packaged archive. Independent plist/lipo inspection confirmed those architectures. [Local artifact report](ghostty-local-artifact.json) records slice hashes and toolchain versions.

The iOS-only archive is 22,915,836 bytes (22.9 MB decimal), SHA-256 `3d4620a7fa8441aae6a5f6f149e605692bcd2dbd265d42e558833417774812c4`. The uncompressed iPhone static archive is 19,452,928 bytes and combined simulator archive 39,136,760 bytes. These are dependency artifact sizes, not installed-app, App Store or incremental executable sizes. This was one successful source reproduction, not a repeat-build determinism proof.

An isolated app copy used the rebuilt wrapper's Package.local.swift and local BinaryTarget, with the Xcode package reference changed only in that copy. Initial package refresh encountered a GitHub SSH fetch failure; that resolver was deliberately stopped. An independent copy of the existing package cache was then verified against every tracked checkout revision. The local wrapper used exact MSDisplayLink 2.2.0 with its existing resolved revision `87eb0af130744c8cbe2e31b6e1a5bcd659f1c220`. The retry used `-disableAutomaticPackageResolution -skipPackageUpdates`; all nine remote resolved revisions matched tracked pins.

The unsigned generic-iPhone consumer build passed. Its build log explicitly identifies the local Ghostty package and processes the locally rebuilt BinaryTarget XCFramework. Two UI tests then passed on the iPhone 17 Pro / iOS 26.5 simulator: `testRealTerminalParserAndInputPaths` (7.992 s) and `testTerminalKeyboardDismissalAndExpansion` (56.757 s). These durations are test execution time, not terminal latency. No physical phone has run this self-built artifact yet. The main repository dependency pin and installed phone artifact remain unchanged.

To reproduce the consumer check, make an isolated copy of the app and wrapper sources, copy the rebuilt BinaryTarget, use Package.local.swift as the local wrapper manifest, and reference it through XCLocalSwiftPackageReference in the copied project. Preserve all resolved dependency revisions. With a separately copied and revision-verified package cache, use the following build settings on the copied project:

```sh
xcodebuild build -project "$consumer_project" -scheme MoshDeckSpike \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$consumer_derived_data" \
  -clonedSourcePackagesDirPath "$verified_package_cache" \
  -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO
```

The variables name disposable consumer/project/cache paths chosen by the engineer. Code signing is intentionally disabled for this compilation check; it is not an installation recipe. Runtime qualification of a replacement phone artifact still requires the physical acceptance matrix.

The wrapper license check confirms its tracked-resource policy, not all native static-library licenses. Original MIT wrapper/core notices, the MIT shell-integration rewrites and vendored bash-preexec notice must accompany distribution as applicable. Complete native/font/transitive notices and link/resource audit remain pending; see [license review](licenses.md).

## Upgrade contract

Change wrapper/core/artifact pins together only after reviewing the exact upstream diff, chosen patch variants, resource/license changes and minimum toolchain. Independently verify the new artifact hash, rerun source reproduction, compare headers/slices/resources, and run core plus physical terminal/clipboard/keyboard/resize/reconnect checks. Keep the previous working pin recoverable. Never accept a checksum mismatch, floating version, silent patch failure or trust-all transport workaround.
