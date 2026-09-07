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

## Additional native notices — 2026-09-07

`Spike/App/Notices/NativeLibraries.txt` retains 11 source notice files for Ghostty core, FreeType, libpng, zlib, Oniguruma, Highway and Wuffs. [native-library-notices.json](native-library-notices.json) records source paths, source-file hashes, Zig package hashes and cached-archive SHA-256 values. These were collected from the pinned core revision and the dependency archives used by the successful local rebuild. FreeType's license introduction and FTL text are both included; this inventory uses the FTL path, not a claim that Ghostty's MIT license covers FreeType.

Archive-member inspection supports these native dependencies: `ftbase.o`, `png.o`, `inflate.o`, Oniguruma regex/encoding objects, `libhighway_zcu.o`, and `wuffs-v0.4.o` are present in the rebuilt iOS arm64 archive. This is archive inclusion evidence; final Release dead stripping and component-level source attribution still need their own review.

A concrete metadata discrepancy was identified (reproduction result below): `pkg/simdutf/build.zig.zon` declares version 5.2.8, while the vendored `pkg/simdutf/vendor/simdutf.h` defines `SIMDUTF_VERSION` as 9.0.0. `simdutf.o` is present in the archive. Do not generate a 5.2.8 notice/SBOM entry solely from the package version. Trace the actual vendored source and its embedded third-party notices before completing that component.

After the simdutf reproduction below, the remaining inventory includes stb, pure-Zig/runtime dependencies, symbol-font components and shell resources, plus toolchain/runtime licensing as actually linked. libintl is separately documented above. None of these partial notice additions closes the full distribution gate.

### simdutf discrepancy resolved by reproduction — 2026-09-07

The vendored source is a feature-reduced amalgamation of simdutf **9.0.0**, upstream commit `ca7acbcea967b5dcbab490066e99e3a6e6925539`; the Ghostty package's 5.2.8 value is stale metadata. Direct comparison with the release's full-feature single-header files initially differed. Regenerating from the immutable source with the following command reproduced both vendored files byte-for-byte after removing only their generated timestamp first line:

```sh
python3 singleheader/amalgamate.py \
  --with-utf8 --with-utf32 --with-base64 --with-ascii --with-latin1 \
  --no-zip --no-readme --output-dir regenerated
```

[simdutf-provenance.json](simdutf-provenance.json) records the flags, immutable revisions, full vendored-file hashes and timestamp-excluded body hashes. `Spike/App/Notices/Simdutf.txt` includes the upstream MIT/Apache license texts and the BSD-style instruction-set detection notice embedded in the vendored header. The third-party checkout and app dependency pins were not modified. Other native/resource inventory and static-link distribution review remain open.

## Zig and resource notice inventory — 2026-09-07

`Spike/App/Notices/ZigAndResources.txt` retains 12 notices for libxev, vaxis, zig-objc, uucode, zf, z2d, the Nerd Fonts symbol archive and stb. [zig-resource-notices.json](zig-resource-notices.json) records exact source hashes and archive/revision provenance. These are source-import/resource inventory entries; inclusion in the manifest is not proof that every library survives the final Release linker.

Two package-archive omissions required looking at the immutable upstream revisions:

- z2d's cached source archive omits `LICENSE` and `COPYING`. Its `src/z2d.zig` identifies MPL-2.0 and copyright Chris Marchesi. Both upstream notice files were obtained at `7dbae85c81784dba9988320bf9543ed9a81350c8`, the revision named in Ghostty's source URL. Do not describe the entire native set as permissive-only.
- uucode's `LICENSE.md` references `licenses/LICENSE_Bjoern_Hoehrmann` and `licenses/LICENSE_unicode`, but the cached archive omits those files. They were recovered from the declared upstream revision `2826a37a4562284fdacd8fa029d49509cc9bffcd` and retained alongside the MIT notice.

The two stb headers' complete MIT alternatives were copied directly from the pinned Ghostty source. The Nerd Fonts archive's top-level MIT notice is included, but individual symbol-source license attribution remains a separate open item. Runtime/toolchain, shell resources, final Release linkage and applicable copyleft distribution obligations still require closure.

## Release linkage checkpoint — 2026-09-07

An unsigned arm64 Release build at `285bdf6` completed with `LD_GENERATE_MAP_FILE=YES`. [release-link-audit.json](release-link-audit.json) records artifact/map hashes, sizes and bounded symbol-name observations. The live-symbol section (excluding dead-stripped entries) contains libintl, Wuffs, simdutf, Highway, Oniguruma and libxev names. `_libintl_bindtextdomain` is also a defined symbol in the final executable. libintl therefore remains a Release distribution concern, not merely a Debug artifact finding.

No BoringSSL object references were found in that app link map. No visible live symbol-name matches were found for several other source dependencies, including z2d, uucode and vaxis. These negative substring searches do not establish exclusion: optimized/inlined code and generated tables may not retain the source library's name. Source-import and archive inventories must remain distinct from this narrower final-symbol evidence. The raw map is retained locally, not committed, because it includes machine-specific build paths and embedded binary strings. No phone installation or distribution occurred.

## Symbol-source and compiler-runtime notices — 2026-09-07

The embedded `SymbolsNerdFont-Regular.ttf` identifies Nerd Fonts 3.4.0 and Ryan McIntyre's copyright, but has no license/name-table records 13 or 14. `Spike/App/Notices/NerdFontComponents.txt` now includes the eight license files present under `src/glyphs` at release revision `fa7b859994228a9c8759f99c55a8d31ee92a1b5e`: codicons, Font Awesome, Material Design, Octicons, Pomicons, Powerline Extra, Powerline Symbols and Weather Icons. [nerd-font-notices.json](nerd-font-notices.json) records source hashes. This supplements the already bundled archive-level notice. Other glyph sources without license files in that directory still need attribution tracing; font metadata alone does not supply it.

The Release linker map also attributes 12 live entries to `libghostty.a(compiler_rt.o)`, including Zig platform-version checks, integer conversion/division and stack-protection helpers. The Zig 0.16.0 toolchain used for the local reproduction supplies the MIT license copied unchanged to `Spike/App/Notices/Zig-MIT.txt`. Its SHA-256 is `5c537d6853e005298a285d508cff9ac7192cea23576c840d485b2b586a7ff177`. The signed Debug iPhone build passed and both new notice resources matched their source bytes. C++ and Apple runtime dynamic-library references are distinct from this statically included object; do not assume an external system-runtime reference means no compiler runtime is bundled.
