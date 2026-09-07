# Dependency and distribution review

Observed 2026-09-06. This is an engineering selection review, not a complete distribution clearance. No app license existed at repository inspection. Recommend MIT for original MoshDeck code; confirm dependency notices and shipped artifacts before public distribution. Do not assume a top-level MIT file covers every bundled resource.

| Dependency | Purpose | License | Static-link implications | App Store implications | Maintenance / risk |
| --- | --- | --- | --- | --- | --- |
| [Ghostty core](https://github.com/ghostty-org/ghostty/blob/main/LICENSE) / libghostty-vt | Terminal engine | MIT core; some shell integration files have different licenses | Preserve copyright/license; audit linked third parties | Core license does not itself prohibit linking; private APIs/artifact content still need inspection | Upstream active; embedding API unstable, full iOS unsupported |
| [Lakr233/libghostty-spm](https://github.com/Lakr233/libghostty-spm/blob/733ae3b29d447b6707cbfc00879027a076dfd0eb/LICENSE) | UIKit/Metal and XCFramework | MIT wrapper; bundled core/dependencies need notices | Keep wrapper/core and transitive notices; verify binary provenance | Patch removes private blur API; that is not full App Review approval | Active patch stack, weekly upstream coupling; highest maintenance risk |
| [MSDisplayLink](https://github.com/Lakr233/MSDisplayLink) | Wrapper display scheduling | MIT | Retain notice | No copyleft linking requirement | Additional pinned Swift dependency |
| Ghostty native/font dependencies | C++ runtime, SIMD, fonts and rasterization as built | Mixed licenses, including LGPL-2.1-or-later libintl; determine exact included list from build | Audit link map and archive against source dependency graph | Use Apple public APIs; exclude GPL shell scripts unless intentionally complying | Complete binary SBOM/notice audit remains a release gate |
| [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh/blob/3ec281496f28a3b6581afd946b759e2642f5cd8d/LICENSE.txt) | Selected SSH protocol engine | Apache-2.0 | Retain license/notices and modification notices as applicable | No copyleft relinking requirement | Active upstream, narrow protocol scope |
| [SwiftNIO](https://github.com/apple/swift-nio), [Atomics](https://github.com/apple/swift-atomics), [Collections](https://github.com/apple/swift-collections), [System](https://github.com/apple/swift-system), [Swift ASN.1](https://github.com/apple/swift-asn1) | Network/event-loop and transitive utilities | Apache-2.0 | Retain notices; resolve exact graph | Ordinary native libraries | Track exact resolved revisions |
| [Swift Crypto](https://github.com/apple/swift-crypto) | SSH signing/key exchange/encryption | Apache-2.0; bundled BoringSSL has additional notices | Preserve included third-party notices; Apple-platform CryptoKit path does not excuse auditing artifacts | Encryption export classification must reflect actual app | Pin and inspect platform build; no custom crypto |
| Apple CryptoKit/Security/LocalAuthentication | Platform crypto, Keychain, lock | Apple SDK terms | Platform frameworks, not relicensed app code | Public supported APIs; Face ID usage description when used | OS-supported; device testing needed |
| [libssh2](https://github.com/libssh2/libssh2/blob/master/COPYING) | Alternate SSH engine | BSD-style permissive license | Retain copyright/license | No copyleft linking requirement | Mature; published version lag versus main changes |
| [OpenSSL 3](https://www.openssl.org/source/license.html) | Likely libssh2 crypto backend if chosen | Apache-2.0 | Preserve license/notices; pinned static build | Export classification; not inherently incompatible | Adds independent security/build update burden |
| [libssh](https://github.com/libssh/libssh-mirror/blob/master/COPYING) | Alternate SSH engine | LGPL-2.1-or-later in inspected COPYING | Static distribution needs LGPL compliance, including relink/source obligations as applicable | Resolve distribution terms before adoption; not a blanket ban | Maintained but unnecessary complexity here |
| [NMSSH](https://github.com/NMSSH/NMSSH) | Legacy libssh2 wrapper | MIT wrapper; backend separate | Backend and crypto licenses still apply | No shortcut around binary audit | Upstream last commit observed 2018 |
| [Citadel](https://github.com/orlandos-nl/Citadel/blob/master/LICENSE) | Alternate Swift SSH wrapper | MIT plus Apache/fork/BigInt/bcrypt dependencies | All transitive notices required | No blanket guarantee from MIT wrapper | Extra SSH fork and algorithm implementations |
| [Mosh](https://github.com/mobile-shell/mosh/blob/master/COPYING) | Optional future mobile transport | GPL-3.0-or-later; OpenSSL exception and [iOS commitment](https://github.com/mobile-shell/mosh/blob/master/COPYING.iOS) | Linking into app normally creates GPL compliance obligations; source availability alone is insufficient | iOS commitment addresses App Store terms conflict only; other GPL obligations remain | Do not casually embed into an MIT-only distribution |
| Protobuf / zlib and Mosh crypto backend | Optional Mosh implementation dependencies | BSD-3-Clause / zlib / backend-dependent | Audit selected implementation and exact versions | No automatic coverage by Mosh's iOS commitment | Deferred with Mosh |
| [tmux](https://github.com/tmux/tmux/blob/master/COPYING) | Mac-side sessions | ISC-style, with per-file notices | Not linked into phone app | Separately installed Mac prerequisite | Mature; configuration/versions affect behavior |
| [Tailscale](https://github.com/tailscale/tailscale/blob/main/LICENSE) | External OS VPN | BSD-3-Clause open core; official apps/terms separate | Not embedded/linked | User installs official app; no VPN entitlement needed by MoshDeck | External service dependency; no redistributed Tailscale binary |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm/blob/main/LICENSE) | Terminal fallback | MIT | Retain notice | Existing shipping iOS consumers | Active; current API transition needs pinning |
| [Blink](https://github.com/blinksh/blink/blob/raw/LICENSE) / [Remux](https://github.com/h3nock/remux/blob/main/LICENSE) | App references | GPL-3.0 / MIT | No Blink code copying into permissive app; Remux reuse retains notice | Inspect dependencies independently | References, not selected app forks |

Before distribution, produce notices from `Package.resolved` plus the XCFramework build manifest and link map, verify no unexpected telemetry/private symbols/resources, and complete encryption/export metadata. Avoid adding a blanket `ITSAppUsesNonExemptEncryption = false` without classifying the actual shipped SSH crypto. Current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) also constrain public APIs and background-mode use; working around suspension using fake audio/location is not part of this design.

## Bundled Swift package notices — 2026-09-07

`Spike/App/Notices/SwiftPackages.txt` preserves the top-level license and notice text from all nine packages in the app's `Package.resolved` (12 source files). Each checkout HEAD was verified against its resolved revision before collecting text with `git show REVISION:PATH`. The source-file SHA-256 values and revisions are recorded in [swift-package-notices.json](swift-package-notices.json). The app's synchronized resources group includes this notice file. JetBrains Mono's OFL is bundled separately.

To refresh, resolve the committed app pins, verify checkout revisions, enumerate each revision's top-level `LICENSE`, `NOTICE`, and `COPYING` files using `git ls-tree`, and read those files using `git show`. Preserve their text and update the source hashes in the manifest; do not substitute licenses from a newer default branch. Build the app and verify the resulting resource byte-for-byte.

This closes the top-level Swift-package notice inventory only. Nested C/C++ dependencies, Ghostty's statically linked native libraries, symbol fonts and shell resources still require their own complete inventory. The manifest does not establish that every target of every resolved package is linked into the final app, and it does not constitute distribution clearance.


## Confirmed native copyleft dependency — 2026-09-07

GNU libintl from gettext 0.24 is included in the current iOS build. This corrects the earlier characterization of Ghostty native dependencies as only permissive/system licensed.

Evidence from the exact pinned core and built artifacts:

- `src/build/SharedDeps.zig` adds the static `intl` library on Darwin platforms; `pkg/libintl/build.zig.zon` selects gettext 0.24, Zig package hash `N-V-__8AADcZkgn4cMhTUpIz6mShCKyqqB-NBtf_S2bHaTC-`.
- Both the pinned release's iOS arm64 archive and the locally rebuilt iOS archive contain `gettext.o`, `dcigettext.o`, and other libintl object files. The release archive has 167 members.
- `nm -g` on the current signed Debug app's `MoshDeckSpike.debug.dylib` reports defined `_libintl_gettext`, `_libintl_dgettext`, and `_libintl_bindtextdomain` symbols. This is linked-code evidence, not just an unused package declaration. A future Release binary still needs its own inspection.
- The pinned gettext source's `gettext-runtime/intl/gettext.c` states LGPL version 2.1 or later. Its `gettext-runtime/intl/COPYING.LIB` is copied unchanged into `Spike/App/Notices/Libintl-LGPL-2.1.txt`.

The copied license SHA-256 is `20e50fe7aae3e56378ebf0417d9de904f55a0e61e4df315333e632a4d3555d95`. The signed iPhone Debug build passed and its bundled license matched the source byte-for-byte. The installed phone app was not replaced.

Adding the license text does not close distribution compliance. Before distributing a beta or App Store build, resolve the applicable source/relinking requirements and distribution terms for this actual static-link arrangement. Do not inherit the build script's assertion that open source alone establishes compliance. The reproducible core build is useful evidence but is not a complete compliance determination. No architecture change or dependency removal has been made on this finding alone.
