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
2. Add the required application icon; the archived application has no `CFBundleIcons` entry.
3. Complete the encryption declaration for the actual SSH implementation; the archive does not set `ITSAppUsesNonExemptEncryption`.
4. Resolve the documented static libintl distribution obligations and remaining dependency inventory in [licenses](research/licenses.md). Successful signing does not resolve these requirements.
5. Rebuild/export the final source, verify distribution entitlements and signature, upload with `asc`, and inspect processing before assigning a tester group. Tester invitations are a separate explicit action.

## Initial beta scope

The tested remote workflow is official Tailscale, ordinary macOS OpenSSH, Ed25519 phone identity, strict host-key verification and an existing tmux session. Tailscale is the supported deployment recipe, not an embedded dependency or hard network requirement. Local-network or other VPN access may work through ordinary SSH but has not received the same device acceptance.

What to Test should focus on connection setup, terminal input, composer, keyboard dismissal, background/lock recovery and preservation of the same tmux process. Keep the separate 20/60-minute lock, network-direction, termination, broader terminal and real coding-agent dogfood rows pending until observed. No backend, account system, Mosh transport or agent API is included.
