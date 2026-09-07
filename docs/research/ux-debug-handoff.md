# MoshDeck live UX/debugging handoff

Checkpoint: 2026-09-06 (first successful attempt occurred September 7 UTC). Engineering spike; daily-use acceptance is incomplete.

## Current result

**Physical iPhone SSH shell reached connected.** Manual attempt FDE1FA71 recorded TCP activation, SSH host-key match, public-key authentication success, session channel, accepted PTY, accepted shell and first interactive output. Connect-to-output was 4.466435 seconds in one sample, excluding app unlock. The loaded public-key fingerprint matched the authorized phone key. This first attempt proved the transport/PTY/output path. A later owner report confirms a couple of commands worked, corroborated by connected attempt 58B901AA and a 2.060461-second connect-to-output sample. Phone tmux attachment and concurrent local Mac PTY attachment now retain the original shell PID; iTerm2 UI and mobile recovery remain unverified.

The latest keyboard-control build is installed and reopened with the verified profile and clean interactive shell selected. The owner subsequently unlocked, connected and confirmed command use. Exact command text was not collected.

## Architecture and scope

SwiftUI/UIKit, pinned community GhosttyTerminal, Apple SwiftNIO SSH, official Tailscale apps, ordinary macOS OpenSSH, and tmux. No signup, backend, companion, agent API or Mosh implementation. One active terminal; multiple saved/native session views remain later work. The Mac retains execution and credentials.

## Implemented lifecycle

App lock is independent of connection state. Explicit Unlock MoshDeck grants five minutes; Connect/retry/reconnect do not prompt again within that window. Expiry currently closes transport even in foreground. Keychain holds the private key and a separate profile/draft record. Cold launch starts locked; profile/draft cold-launch restoration remains a manual acceptance gate.

Attempt IDs isolate callbacks. Detailed stages drive progress; first fatal error wins over cleanup. Ordered callbacks, cancellation, bounded retry and sanitized Copy Diagnostics are implemented. Last terminal remains visible during recovery; a successfully reattached candidate replaces it. No input is replayed. See [connection lifecycle](connection-lifecycle.md) for exact stages, retry rules and limits.

## User-observed bugs and disposition

| Observation | Change / evidence | Remaining limit |
| --- | --- | --- |
| Long-press public key did nothing | Explicit Copy/Share added; owner supplied the key afterward | No private key exported |
| Username/host key prefill empty | Missing Swift DEBUG build condition fixed; physical prefill test passed | Saved-profile cold-launch test pending |
| Connect → Face ID → progress → Connect | App unlock separated; structured errors and parent-close observation added; later physical shell succeeded | Original failure had no retained trace; exclusive cause unknown |
| Cleanup could mask startup error | First-failure ownership and stale callback guards | Deterministic tests pass |
| Cancellation waited for startup timer | NIOSSH consumes channelInactive; observing parent closeFuture fixes reproduced stalled-handshake test | Does not uniquely explain original phone loop |
| Diagnostic picker did not select actual mode | Intent routing centralized and unit tested | First phone success was a normal shell, not auth-only |
| Keyboard concealed bottom tabs | Persistent Hide Keyboard control | Physical fixture keyboard-dismissal test passed |
| Too little terminal space | Expand terminal / Restore controls; raw keys remain available | Physical expand/restore test passed; live SSH resize acceptance pending |

## Test evidence

- Core suite: 16 entries, 15 passed and one opt-in actual-Mac test skipped in the default run. Includes root error, stale callback, cancellation, lock grace, diagnostic routing, host mismatch, PTY/resize, Ctrl-C and exact 1 MiB output.
- Separate opt-in actual-Mac OpenSSH runs passed authentication only, echo/no PTY, clean shell, normal shell and disposable tmux. Temporary test authorization entries were removed; these are Mac loopback tests, not phone-network evidence.
- Seven isolated tmux checks passed. Physical-phone tmux attachment subsequently passed, with a second Mac PTY client and unchanged shell PID.
- Physical iPhone 15 Pro Max / iOS 26.6: synthetic terminal parser/input fixture, 30-second background composer retention, prior profile prefill, app-lock gating, and keyboard dismissal/expand/restore passed.
- An earlier automated phone connection test failed waiting for human app unlock before SSH. The later manual shell success supersedes that connection gate; the failed automation is retained as history.
- Tailscale probes reached the phone through DERP in a sampled 158–242 ms range. This is not typing latency or a direct-route guarantee.

Detailed evidence and unrun scenarios: [physical device investigation](physical-device-connection-debug.md). Research and recommendation: [architecture](../architecture.md), [security](../security.md), [spike results](spike-results.md).

## Next acceptance sequence

1. Unlock and connect to the clean shell; type echo hello and uname -a. Confirm returned output and keyboard dismissal/expansion while SSH stays usable.
2. Attach the disposable tmux session; verify Mac/phone handoff and resizing before any coding-agent task.
3. Record 30-second background, five-minute lock, Wi-Fi/cellular handover, one-minute outage and kill/reopen separately, including unlock, reconnect, draft/screen retention and time to usability.

No new UI framework, service or agent integration is needed to complete this sequence.


## Latest recovery evidence

The owner reports recovery worked. Two later phone attempts successfully reattached to tmux, taking 4.247 s and 2.657 s from attempt start to output; Mac shell PID 89665 remained unchanged. The longer disconnect-to-next-attempt gap was 98.850 s. Exact foreground timing and automatic/no-additional-auth behavior are not established: the unlock deadline changed, and owner clarification is pending. Do not equate successful reattachment with passing the entire background/network matrix.


## Cellular check and profile restoration

The owner reports success after the instructed Wi-Fi-off/cellular test. Attempt E947583E retained its connection through an inactive/active interval, with no second unlock or SSH attempt in the captured timeline. Original tmux shell PID remains 89665. Network-interface choice is owner-reported, not measured by the app. The build launch omitted host/user/trust/session overrides, corroborating saved-profile restoration through successful connection; draft restoration remains separate.


Owner clarified that Connect required a manual tap and that this is acceptable for now. Report manual connect/reconnect as working; do not advertise automatic recovery as verified. The latest trace explicitly records a manual trigger. Whether the tap was initial post-relaunch connection or interruption recovery remains unspecified.


Final owner clarification for this checkpoint: recovery works and did not require Face ID again. Manual Connect is acceptable during the spike. Record the successful no-repeat-auth recovery as owner-confirmed, retaining the independent Mac/process and phone-timeline evidence above. Next gate is deliberate five-minute phone lock and recovery.


## Latest definitive lifecycle evidence

Automatic recovery is now verified for one measured 116.288-second background interval: foreground resume triggered SSH/tmux reattachment in 2.340 seconds with no additional unlock request. The five-minute unlock deadline later expired, the owner authenticated, and another automatic foreground resume restored tmux in 2.607 seconds. Original shell PID 89665 remained unchanged. These source-labelled events supersede earlier uncertainty about automatic versus manual recovery for these specific runs. They do not substitute for a continuous five-minute screen-lock or full outage test.
