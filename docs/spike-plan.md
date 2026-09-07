# First engineering spike

Research-first plan dated 2026-09-06. This is the requested tracked spike design, not a promise that device tests have run. [Architecture](architecture.md) and [product direction](product-direction.md) define the hypothesis. [Results](research/spike-results.md) records actual evidence.

## Objective and stop rules

Prove a real iPhone can render and operate the Mac's existing tmux workspace through Ghostty + SSH over Tailscale, then regain control after interruptions. Do not spend time on icons, onboarding, polished settings, agent detection, files, TestFlight, Mosh code or notifications.

If the patched Ghostty frontend cannot build/use public APIs or fails core input/rendering tests, record the failure and evaluate SwiftTerm as a replacement before adding UI features. If the controlled Mac needs SSH capabilities absent in NIOSSH, evaluate libssh2. If device networking is unavailable, continue independent component tests but leave the physical gate open. Never substitute a simulator or desktop TCP test for a phone result.

## Exact sequence

1. **Freeze evidence.** Save versions/revisions and artifact hashes for GhosttyTerminal, its core/patches, NIOSSH and resolved dependencies. Confirm current source API, not an old example. Inspect dependency notices and disable payload debug logs/file staging.
2. **Existing-client baseline.** On the real phone, use Blink (or already-owned comparable client) through official Tailscale to the same Mac/tmux session. Run short reconnect, large prompt, raw keys and full-screen checks. If it already meets the need, building remains optional.
3. **Frontend-only harness.** Build a minimal SwiftUI app with a UIKit Ghostty terminal using the host-managed session. Feed deterministic ANSI/Unicode data in adversarial chunk boundaries. Capture outgoing encoded keys and protocol replies in tests without logging user content. Build for generic iOS device and simulator. On device inspect actual glyphs/selection/keyboard/Metal.
4. **SSH component.** Add pinned Apple NIOSSH, generated per-phone Ed25519 identity, explicit pinned host key, connect/auth/PTY request-reply handling, raw stream, window resize and clean close. Validate against an isolated local OpenSSH fixture with temporary keys, including wrong-host-key rejection before auth. Do not use a trust-all callback even for the spike. A loopback fixture must not change the Mac's real authorized_keys or sshd configuration.
5. **Join bytes.** Connect SSH stdout to Ghostty receive and Ghostty encoded input/replies to SSH stdin, preserving order/UTF-8 boundaries/backpressure. The app needs only a minimal host/session input, Connect/Disconnect, status, terminal, raw-key row and a plain multiline composer. In the harness paste can initially be exercised by fixture actions before UX work.
6. **tmux handoff.** Use an isolated test tmux server for automated semantics. Verify same pane PID through client loss/reattach, current screen redraw, missing-session detection and resize. Then test the real user's ordinary iTerm2 setup on device with a disposable working session; start Codex only there with the owner's chosen permissions. Never start an autonomous agent against a real repository just to test rendering.
7. **Lifecycle.** Implement generation-scoped coordinator, no offline input, no replay, fresh surface on reconnect and close-on-background baseline. Hide content on resign-active. Require local unlock before connection/key use. Persist only profile/session identity and protected composer draft, not transcript. Unit-test late callbacks, lock/background races, cancellation, mismatch/auth terminal failures and ambiguous paste completion.
8. **Physical matrix below.** Use official Tailscale, real Wi-Fi/cellular and screen locking. Record each result with time, device/OS/build, server/tool versions and route where known. Recheck SSH-only behavior before considering Mosh.
9. **Measure and revise.** Profile synthetic output and ordinary typing in Instruments on device. Compare to baseline. Update architecture decision with measured failures/benefits and keep unknowns explicit.

## Physical-device matrix

Every row starts NOT RUN until a witnessed run establishes a result. Record pass/fail/blocked separately; do not infer one row from another.

| ID | Scenario | Acceptance |
| --- | --- | --- |
| 1 | Wi-Fi connect -> tmux -> Codex | Verified host/key auth, correct interactive UI, same pane PID |
| 2a | Start task -> Wi-Fi to cellular -> type | Work continues, no replay, usable recovery timing |
| 2b | Cellular to Wi-Fi -> type | Same; reverse direction independently tested |
| 3 | Active terminal -> lock 5 minutes | Protected UI/key, same remote process, reattach |
| 4 | Lock 20 minutes | Same; record warm or cold app return |
| 4b | Lock/idle 60 minutes | Same; distinguish foreground idle from lock |
| 5 | Complete disconnect -> reconnect | Existing session attached; absence reported without recreation |
| 5b | Airplane mode 2 minutes | No offline raw input; explicit recovery |
| 5c | Switch apps 30 seconds | Correct privacy cover and recovery |
| 5d | Force terminate/relaunch | Protected saved profile/draft only; fresh SSH/terminal |
| 6 | iTerm2 and phone attached | Same process; document geometry and window selection effects |
| 7 | Detach phone, continue Mac | Phone loss does not kill remote task; Mac size restored |
| 8 | Detach iTerm2, continue phone | Phone still controls same pane |
| 9 | Large synthetic/Codex output | No corruption, bounded memory, responsive interrupt |
| 10 | 500-word and 64 KiB prompt | Native editing/dictation/selection; paste delimiters and Enter correct; no automatic resend |
| 11 | Ctrl-C in disposable agent task | Byte/control-key semantics correct; no accidental session kill |
| 12 | vim, nvim, htop, less | Alternate screen, resize, cursor, colors and return to shell correct |
| 12b | Claude Code UI | Correct rendering, paste and control keys if installed; otherwise explicitly unavailable |
| 13 | Host-key substitution | Block before credentials, no auto-trust on reconnect |
| 14 | Hardware keyboard / VoiceOver / IME | Esc/Ctrl/Alt/arrows/modifiers, CJK composition and labelled controls |

Test Unicode/CJK/combining/emoji/double-width, terminal replies, bracketed paste, OSC titles/hyperlinks, mouse reporting, scrolling, scrollback, cursor shapes, true color and xterm-256color in the same build. Exercise selection without inadvertently sending mouse clicks. Use synthetic content for screenshots/profiles.

## Performance record

For each condition collect sample count, median/p95 where applicable, measurement method and environment. Initial targets are investigation thresholds, not claims:

| Metric | Method | Initial target / decision use |
| --- | --- | --- |
| Local key dispatch / display | Signposts + Instruments; distinguish local frame from remote echo | No main-thread stall; roughly one frame dispatch when uncongested |
| Remote typing latency | Timestamp input and observed echo in controlled echo fixture; correlate route RTT | Near transport RTT; compare to Blink; Mosh prediction assessed separately |
| Reconnect | Path restored -> first interactive tmux redraw; separate Face ID delay | p95 <= 5 seconds on ordinary connection; investigate repeated >10s outages |
| Output throughput | Synthetic 1/10 MiB bursts, bytes/time and render completion | No dropped bytes/unbounded queues; Ctrl-C remains usable |
| Resize latency | Grid callback -> remote stty/tmux size -> redraw | Correct final geometry, no resize storm |
| CPU/memory | Instruments while idle, sustained output, scrolling, background/resume | Stable memory with bounded scrollback; render stops in background |
| Battery | Physical-device energy profile with brightness/route/workload recorded | Compare like-for-like to baseline; no simulator battery inference |
| Binary footprint | XCFramework slice, linked release executable, archive and device install | Distinguish 77 MB multi-platform download from per-device footprint |

Run unit tests for meaningful state/input/trust races, component interoperability against OpenSSH, and relevant simulator tests once each revision is stable. Record command/result and raw failure context locally; only synthetic fixtures may produce payload logs. Release approval/signing is not the spike objective.
