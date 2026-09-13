# Minimal terminal spike

This is an investigation harness, not the daily-use MVP. Read [architecture](../docs/architecture.md), [plan](../docs/spike-plan.md), and [actual results](../docs/research/spike-results.md).

## Build and local checks

Requires an Apple Silicon Mac, Xcode 26.6 with its Metal toolchain, and Zig 0.16.0 for the currently tested dependency recipe; targets iOS 18+. Dependency versions and transitive revisions are locked. No project generator is required. Prepare the native dependency once per fresh checkout before opening/building the Xcode project:

```bash
python3 Spike/scripts/prepare-ghostty.py
swift test
python3 Spike/scripts/check-tmux.py
xcrun swift-format lint --strict --recursive Sources Tests Spike/App Spike/UITests Package.swift
xcodebuild build -project Spike/MoshDeckSpike.xcodeproj \
  -scheme MoshDeckSpike -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

The generated Swift package and XCFramework live in ignored `.build/ghostty-ios/package`. The project consumes that local package; it no longer downloads the upstream release XCFramework. The recipe uses exact upstream commits plus the checked-in conditional-libintl patch, disables gettext localization, and records provenance. It refuses to overwrite an existing build directory. See [dependency evidence](../docs/research/licenses.md) before upgrading.

For runtime testing choose an available simulator/device destination in Xcode. An actual device build needs your development team/signing; no personal team is hardcoded into the project. The UI test runs the synthetic fixture and retains its screenshot in the result bundle. Never share whole Xcode diagnostic bundles without inspecting them for unrelated device data.

`swift test` starts an ephemeral loopback OpenSSH daemon using temporary keys and a forced disposable shell, then removes it. It does not edit the real SSH configuration or authorized_keys. The tmux script uses its own socket namespace and empty configuration; it never attaches to existing sessions.

## Fixture tab

The host-managed Ghostty surface receives synthetic ANSI/UTF-8 data. The fixture checks split input, alternate-screen restoration, Ctrl-C, bracketed large paste, and a distinct Enter key. The screenshot helps assess actual rendering but does not certify the full terminal-correctness matrix. No network or credentials are used by this tab.

## SSH tab

1. Enable the official Tailscale apps separately and ensure the Mac is awake with Remote Login configured for your user.
2. Tap Unlock MoshDeck to authenticate for foreground use, with a five-minute inactive/background grace, then tap Unlock / show phone public key. The app creates a dedicated Ed25519 key in device-only, when-unlocked Keychain storage after device-owner authentication. Use the explicit Copy public key or Share public key button to transfer it; long-press selection is not required.
3. Install that **public** key in the intended Mac account's authorized_keys using your normal trusted setup flow. Never copy the Mac's private keys to the phone.
4. Obtain the Mac's OpenSSH **public host key** through a trusted local channel. Verify its SHA-256 fingerprint independently, then paste the full public key into the spike. Unknown or mismatching identities do not auto-enroll.
5. Enter host, username and port. Begin with Authentication only, then Echo command and Clean interactive shell; enable tmux only after these succeed on the phone. Enter the tmux target. Start existing work in tmux on the Mac first. Create-if-absent is an explicit initial option; reconnect is attach-only.
6. Connect, exercise raw keys and use the composer. The spike exposes Paste and a separate Enter key, with a multiline warning. It never resends failed writes automatically.

The terminal transport has bounded queues, PTY resize, a foreground liveness check, structured stages and attempt-owned callbacks. Copy Diagnostics exports sanitized attempt timelines. See [lifecycle policy](../docs/research/connection-lifecycle.md). Backgrounding closes the connection and returning attempts a fresh authenticated attach. Runtime interruption schedules at most five foreground retries while the app remains unlocked. Initial and permanent failures require explicit retry. Wi-Fi/cellular recovery still needs physical measurement.

## Mac session quick reference

In a normal iTerm2 or Terminal tab:

```sh
tmux list-sessions
tmux attach-session -t work
```

Use the same session name in MoshDeck. Start new persistent work inside `tmux new-session -A -s work` before launching your coding assistant; an existing process outside tmux cannot be adopted. When already inside tmux, Ctrl-B then S opens the session picker (on iPhone: tap Ctrl-B, type lowercase s, choose with arrows and Enter). Ctrl-B then D detaches a client without ending its remote work. Reconnect uses the saved profile target, not a session selected only through the live picker.

## Deliberate limits

- One host profile, one terminal and composer draft. Profile/draft data now uses device-only Keychain storage; cold-launch restoration still requires physical acceptance.
- No combined Paste + Enter until asynchronous paste confirmation completion is handled and tested. No command execution acknowledgement or exactly-once delivery claim.
- Minimal key row; advanced keyboard mapping, text selection, hyperlinks, accessibility and sustained-output behavior still need the required acceptance tests.
- Remote clipboard reads/writes and automatic URL detection are disabled. File/image drops are disabled; paste reads explicit text only. No terminal payload logs.
- Software Ed25519 key, not Secure Enclave. App unlock stays valid throughout foreground use. Five minutes inactive/backgrounded requires authentication on return; network retries never invoke Face ID themselves.
- No custom backend, embedded VPN, Mac daemon, Mosh, Codex API, notifications or file UI. TestFlight preparation is now authorized; production release and full daily-use acceptance remain incomplete.

The physical Wi-Fi/cellular/lock and real iTerm2/agent tests are still required. A successful fixture does not establish a usable remote workflow.


For a verified development-device profile, `MOSHDECK_SPIKE_MODE=tmux` selects attach-only startup to `MOSHDECK_SPIKE_SESSION` using `MOSHDECK_SPIKE_TMUX`. This Debug-only launch override never creates an absent session and does not bypass app unlock or host verification. The selected profile is saved through the existing Keychain path when Connect is tapped.
