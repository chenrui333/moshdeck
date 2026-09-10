# TestFlight preparation

On September 9, the owner authorized preparing a TestFlight beta using `asc`, with further physical acceptance collected through beta testing. This does not mark the daily-use MVP or the remaining lifecycle matrix complete. Git pushes and production App Store submission are not part of this checkpoint.

## Current checkpoint

- Source: `29f459b`; version 0.0.1, build 1.
- Bundle identifier: `com.chenrui333.MoshDeckSpike`, retained to preserve the existing application identity.
- App Store Connect API authentication works. The explicit bundle identifier was registered successfully.
- No MoshDeck app record existed at inspection. The Apple web session needs fresh authentication before first-record creation through `asc web apps create`.
- Release archive and App Store Connect distribution export both succeeded. Export is preparation, not an uploaded or processed TestFlight build.
- IPA SHA-256: `20260bb66ae6ff05e8dc4d29c751534b864f7d64bab9cc0fbbf73e9be9a3f816`.
- Existing core regression run reported 32 tests, including the opt-in integration skip. Physical connectivity recovery is recorded in [device findings](research/physical-device-connection-debug.md).

Archives, exported IPA, provisioning material and raw signing logs remain outside Git. The installed physical-phone build was not replaced during this preparation.

## Before upload

1. Create the App Store Connect record with the existing bundle identifier after secure local web authentication. Do not put Apple passwords or two-factor codes in chat or repository files.
2. Re-archive with the beta icon added after the initial export; that earlier IPA has no `CFBundleIcons` entry.
3. Complete the encryption declaration for the actual SSH implementation; the archive does not set `ITSAppUsesNonExemptEncryption`.
4. Integrate and validate the tested conditional-libintl candidate through a reproducible dependency path, or resolve the current artifact's static-link distribution obligations. The candidate passes device consumer build and two simulator fixtures, but the app still pins the original binary. Complete the remaining inventory in [licenses](research/licenses.md). Successful signing does not resolve these requirements.
5. Rebuild/export the final source, verify distribution entitlements and signature, upload with `asc`, and inspect processing before assigning a tester group. Tester invitations are a separate explicit action.

## Initial beta scope

The tested remote workflow is official Tailscale, ordinary macOS OpenSSH, Ed25519 phone identity, strict host-key verification and an existing tmux session. Tailscale is the supported deployment recipe, not an embedded dependency or hard network requirement. Local-network or other VPN access may work through ordinary SSH but has not received the same device acceptance.

What to Test should focus on connection setup, terminal input, composer, keyboard dismissal, background/lock recovery and preservation of the same tmux process. Keep the separate 20/60-minute lock, network-direction, termination, broader terminal and real coding-agent dogfood rows pending until observed. No backend, account system, Mosh transport or agent API is included.

## Beta icon checkpoint

Added an original geometric terminal icon and MoshDeck display name, preserving the bundle identifier. The reproducible generator is `Spike/scripts/generate-app-icon.swift`. Its initial 24-bit AppKit drawing context failed; the corrected generator uses a 32-bit Quartz context with no alpha channel. The resulting PNG is 1024×1024 and was visually inspected. A Release device-target build succeeded and its generated Info.plist contains both iPhone and iPad primary-icon entries. The earlier exported IPA has not been replaced or uploaded.

## Encryption implementation evidence

The first arm64 Release archive links Apple's system CryptoKit and Security frameworks. Its undefined-symbol table includes CryptoKit references. In the pinned Swift Crypto 4.5.2 package, the ordinary Apple-platform `Crypto` API re-exports CryptoKit; NIOSSH's AES-GCM transport implementation calls that API. Earlier Release link-map inspection found no BoringSSL object references. MoshDeck therefore must not be described as shipping a separate BoringSSL implementation merely because Swift Crypto contains one for other targets.

The app still implements SSH protocol handling through SwiftNIO SSH and intentionally provides encrypted remote terminal access. Official Tailscale is a separate installed VPN application and is not shipped in this binary. These are the facts to use for App Store Connect's encryption questionnaire; this checkpoint does not assert that the entire app automatically qualifies as OS-only encryption or set an exemption flag without completing that determination.

Apple's current [export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/) requires a determination for encrypted beta distribution and provides a questionnaire based on implementation and intended availability. Its [documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption) distinguishes Apple-OS crypto from separately implemented standard algorithms. Complete the questionnaire for the actual build and distribution scope before recording the final Info.plist declaration. References checked September 9, 2026.

## Local dependency preparation recipe

`python3 Spike/scripts/prepare-ghostty.py` prepares a local Swift package under ignored `.build/ghostty-ios/package` on an Apple Silicon Mac with Zig 0.16.0, Xcode and its Metal toolchain installed. It fetches exact wrapper/core commits, applies the upstream patch stack and conditional-libintl patch, builds arm64 device and simulator libraries, rejects gettext symbol matches and writes `provenance.json` with tool versions and artifact hashes. Use `--output` for a different fresh destination. The script refuses to overwrite an existing directory, including a failed run, so evidence is preserved. Native build output and source checkouts are not committed.

The complete fresh-checkout validation passed on September 9: both native libraries, gettext symbol checks and XCFramework packaging completed successfully. The main project still references the upstream binary package; writing this recipe does not change that reference or establish that a beta uses the candidate.
