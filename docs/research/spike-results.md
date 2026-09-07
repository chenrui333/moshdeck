# Investigation and spike evidence

Status on 2026-09-06: research documents and minimal component spike implemented. Generic iOS/simulator builds and local OpenSSH/tmux component tests have passed; a basic frontend runtime test has passed on both simulator and physical iPhone; the joined SSH app also builds and passes the basic physical frontend test. The full remote workflow remains unverified. No full physical workflow acceptance exists yet.

## Repository and local capabilities

- Initial checkout: clean `main`, commit `808927f`, only `README.md` tracked. No app, tests, license or project-specific instructions discovered.
- Xcode reports 26.6, build 17F113. Local CLI reports Codex 0.153.4 and tmux 3.7c.
- The paired iPhone 15 Pro Max was initially unavailable, then became available over USB. The signed spike was installed and its basic frontend test passed. The additional native composer background/draft test also passed on the physical phone.
- Installed official Tailscale reports 1.102.3; its read-only status reports `Stopped`, self offline, zero peers. No VPN state, grant, sshd, power policy or personal credentials changed.
- Worktrunk and distill-litellm were not found on PATH. No PR, branch mutation, commit or push performed.

## Source evidence already collected

- Ghostty current source explicitly rejects full iOS builds and supports VT-only iOS. VT header labels its API unstable.
- Community GhosttyTerminal wrapper supplies UIKit, Metal and host-managed I/O through a patch stack; archive metadata reports 77,133,914 bytes and the manifest checksum matches release metadata. The pinned artifact was downloaded and linked successfully into simulator and physical-device builds; a reproducible source rebuild and complete binary notice audit remain pending.
- Apple NIOSSH release 0.15.0 and its source expose PTY/resize, Ed25519 and Darwin Secure Enclave P-256 construction.
- Remux source implements a closely related MIT iOS product using Ghostty and a Citadel fork with tmux control mode.
- Current Apple background documentation explicitly covers suspension and finite continued processing. Current Tailscale documentation distinguishes ordinary OpenSSH from CLI-distribution Tailscale SSH server support on macOS.

## Open gates

The physical frontend subtest passes; all end-to-end device matrix scenarios in [spike plan](../spike-plan.md) remain NOT RUN. The minimal harness and component/build tests are complete. Required follow-up is to activate an authorized Tailscale path and configure the host identity, then perform physical handover/lock tests with the owner. No missing metric is represented as zero, no simulator run counts as a real-phone pass, and no suggested threshold is reported as measured performance.

## Component experiments

| Experiment | Actual result | Scope limit |
| --- | --- | --- |
| Generic iOS Simulator frontend build | PASS using Xcode 26.6 and pinned GhosttyTerminal | Compile/link only |
| Generic iOS device Release frontend build, unsigned | PASS | Not an installed or executed phone app |
| Isolated tmux 3.7c test server | Seven checks PASS | Local synthetic PTYs, not iTerm2/phone |
| Swift 6 core tests | Six tests PASS, including one seven-case parameterized test | Mac component tests |
| OpenSSH interoperability | PASS: Ed25519 auth, verified host key, shell PTY I/O, resize to 93 columns/31 rows, post-close input rejection, substituted host key rejected | Loopback daemon with temporary keys, forced disposable shell and no changes to real sshd/authorized_keys |
| Simulator frontend runtime | PASS: 1 UI test, zero failures/skips, iPhone 17 Pro / iOS 26.5 | Initial test build mixed x86_64 app with arm64 package objects; Debug active-architecture fix resolved it |
| Physical frontend runtime | PASS: final run has 2 UI tests, zero failures/skips, iPhone 15 Pro Max / iOS 26.6 (23G71) | Synthetic parser/input and 30-second background draft retention only; no SSH/Tailscale workflow or broad glyph/performance conclusion |

Commands: `swift test`; `python3 Spike/scripts/check-tmux.py`; `xcodebuild build/test -project Spike/MoshDeckSpike.xcodeproj -scheme MoshDeckSpike` with explicit simulator/device destinations. Generated build/test bundles live outside the repository. Exact dependency pins are in `Package.resolved` and the Xcode workspace's `Package.resolved`; upstream research commits are in [source snapshots](source-snapshots.json).

The first negative SSH test exposed loss of the original host-key mismatch behind a channel-close error. The adapter now preserves the startup failure, and the assertion passes. This is an error-reporting correction, not evidence that the earlier implementation accepted the wrong key.

The synthetic frontend-only unsigned Release bundle measured 9,543,324 bytes, with a 9,505,864-byte executable. The uncompressed XCFramework iOS arm64 slice files totalled 19,498,214 bytes. These were measured before SSH app integration and exclude that integration and do not measure App Store download or installed footprint, memory, latency, CPU or battery.

Physical frontend evidence was checked with `xcresulttool get test-results summary`, not inferred from an Xcode process exit. The result contains `totalTestCount: 1`, `passedTests: 1`, `failedTests: 0`, `skippedTests: 0` for a physical iOS device. Xcode also reported a diagnostic-bundle collection error after the passing test; that is not a failed test, and the diagnostic archive must not be shared because it may contain unrelated device information.

## Joined spike and further local evidence

The app now has a separate SSH tab wired to the Ghostty host-managed stream, with Keychain identity creation after device-owner authentication, externally supplied host-key pinning, PTY resize, bounded ordered input, backpressured output, a no-command SSH liveness probe, close-on-background, foreground reattach, and a generation-scoped paste action. Profiles/drafts are deliberately memory-only and combined Paste + Enter is not implemented. See [spike usage and limits](../../Spike/README.md). The joined app builds for iOS Simulator and a signed physical iOS target.

A second physical run of the synthetic frontend test in the SSH-enabled app passed (1 test, zero failures/skips). Its exported screenshot was inspected: the sample CJK characters, combining accent, emoji and green true-color label display without an obvious defect. This is a small visual sample, not comprehensive Unicode/terminal certification. The screenshot is retained locally in the test result rather than committed with the phone's unrelated status-bar metadata.

The reviewed local suite has six tests (including the seven-case session-name test). A synthetic loopback OpenSSH transfer verified every byte of a 1,048,576-byte payload; one sample completed in 0.194641167 seconds, approximately 5.1 MiB/s. This includes shell command startup and local transport/consumer work and excludes Ghostty rendering and the mobile path. It is not a mobile throughput, latency, CPU, battery or p95 result. The same test sent Ctrl-C to a disposable remote `sleep 30` and observed the shell accept the next command within the test deadline.

The final physical run completed after the phone became available. `xcresulttool get test-results summary` reports two tests passed, zero failures and zero skips on the iPhone 15 Pro Max / iOS 26.6. The native composer test typed a synthetic draft, spent 30 seconds on the Home screen, reactivated the app and verified the same draft; it passed in 42.341 seconds. The parser/input fixture passed again in 5.117 seconds. This covers frontend/draft behavior only: no SSH connection was active, no five-minute lock or process termination was tested, and it does not close the remote lifecycle matrix rows.

## Current open gates, without reinterpretation

- Phone-to-Mac SSH has not been exercised. During assisted setup, the existing App Store Tailscale 1.102.3 client authenticated and reached Running with the Mac online. After owner setup, the iPhone reports online and macOS Remote Login responds with OpenSSH 10.3. Three Mac-to-iPhone Tailscale probes succeeded through DERP in Hong Kong at 222, 158 and 242 ms; the command reported that a direct route was not established. These are Tailscale probe samples, not SSH typing latency or a phone-to-Mac application connection. Phone public-key authorization and the actual SSH host profile remain pending.
- Existing Blink/Remux baseline has not been tested on the phone.
- Wi-Fi/cellular in both directions; 5/20/60-minute locks; airplane mode; app termination with remote work; actual iTerm2/Codex/Claude/full-screen application handoff remain NOT RUN.
- Sustained rendering, large mobile paste, hardware keyboard/IME/VoiceOver, resize under real workloads, CPU/memory/battery and mobile latency remain unmeasured.
- Patched Ghostty artifact rebuild/complete binary license-notice audit and production hardening remain future adoption/release gates, not reasons to claim this spike is a daily-use application.

The recommendation remains conditional: proceed with SSH + tmux over Tailscale and the pinned community Ghostty frontend for device testing. No evidence yet justifies Mosh, tmux control mode, a companion, agent APIs or a custom backend.

## Assisted network setup follow-up

The existing macOS app bundle identifies the App Store distribution; no second Tailscale installation was added. The connection command initially timed out while browser authentication was pending, but a subsequent authoritative status read reported Running and Self Online. This establishes Mac VPN setup, not phone reachability or an SSH session. macOS Sharing settings were opened for the owner to enable Remote Login; no system SSH configuration or authorized keys were changed. Personal tailnet/device identifiers are intentionally omitted from this portable record.

With Remote Login enabled by the owner, a disposable `moshdeck-spike` session was created in the ordinary tmux server, using `/bin/zsh -f` in `/tmp` and per-window `window-size latest`. No coding agent or repository task was started. This prepares a target for physical attachment; it does not establish handoff acceptance. The first window-option command omitted the session/window colon and failed; the corrected exact session window target succeeded.

## Public-key transfer usability correction

The owner reported that long-pressing the displayed phone public key had no effect. The spike now provides explicit Copy public key and Share public key buttons, progress/result text, and protection against repeated unlock requests. The public-key preparation path also no longer silently exits merely because SwiftUI has not yet reported the scene active after successful authentication; it still refuses background preparation and does not change terminal authentication. The updated signed device build passed, installed successfully and launched on the physical iPhone. Actual clipboard transfer and SSH authorization are still awaiting owner interaction; install success is not a clipboard or connection pass.

## Phone public-key authorization

The owner supplied the phone-generated Ed25519 public key after the explicit copy-button update. Its SSH wire encoding was validated and the public key was appended to the Mac account's authorized_keys under an exclusive file lock, preserving existing entries; permissions are 0600. No private key was transferred. An Ed25519 host-key scan through the Mac tailnet hostname matched the locally read OpenSSH public host key. Phone authentication and terminal attachment are still untested: authorization-file setup and host-key comparison alone do not prove an SSH client connection.

## Connection startup lifecycle correction

Source review found that successful LocalAuthentication could return while the SwiftUI scene was still inactive, causing an early return with the connection marked busy. Startup now waits up to one second for the active callback, checks the connection generation throughout, and clears the attempt with an explicit retry message if activation does not arrive. Later interrupted startup paths also clear the same generation rather than leaving a busy form. The signed device build and formatting checks passed. This build was initially held while the owner entered settings. After the owner reported that Connect had no effect, the correction was included in the subsequently installed setup build; physical authentication/resume behavior remains unverified.

## Prefilled physical connection retry

After the owner reported that Connect had no effect, the signed spike was rebuilt, installed and launched with a debug-only environment-supplied host profile. The profile uses the locally verified Mac public host key and the disposable tmux target; personal host/user values remain outside repository source. This does not bypass Face ID, Keychain or SSH host verification. Connect now sits above the form with a prominent button, larger status text and a cancelable progress indicator. Build, formatting and installation passed; a successful phone SSH connection has not yet been observed. Debug launch settings are still memory-only and need re-supplying after a normal cold launch.

## Verified profile-prefill correction

The owner observed empty username/host-key fields after the first prefilled launch. Source/build inspection found that the hand-written Debug configuration did not define Swift's DEBUG compilation condition, so the debug-only prefill code was compiled out. This corrects the earlier claim that the requested launch environment had populated the form: it had not. The project now defines the DEBUG condition in Debug only. A new physical-iPhone UI test passed (one test, zero failures/skips): it taps Connect with missing fields and verifies the visible validation message, then relaunches with a synthetic profile and verifies all five fields through accessibility values. No network/authentication is attempted by that test. The corrected app was subsequently launched with the owner's locally verified profile. Actual remote attachment remains a separate acceptance gate.
