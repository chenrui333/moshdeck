# MoshDeck executive review handoff

Checkpoint: September 7, 2026, daily-use implementation phase through `e5899e1`. The accepted architecture and physical spike are preserved in Git. Daily-use MVP acceptance is not complete. This report separates installed-device evidence from newer built/tested changes.

## Review request

Act as a principal iOS/terminal/networking engineer and product reviewer. Challenge the design using the evidence below. Prioritize concrete correctness and mobile usability problems. Do not recommend services, frameworks or dashboards without a demonstrated workflow need.

Return:
1. Assess progress toward daily use within the accepted architecture; propose a component change only if new evidence requires it.
2. Up to five findings, ranked by severity, distinguishing observed defects from hypotheses.
3. Defects or acceptance gaps in the implemented foreground-unlimited/background-grace and reconnect policies.
4. The smallest daily-use MVP and explicit exclusions.
5. The next three engineering tasks, each with an acceptance test.
6. Additional evidence needed before your conclusions can be trusted.

## Product objective

An always-on MacBook remains the development/execution host. The iPhone remotely operates the same terminal sessions and coding agents, then the owner returns to the Mac. Raw terminal input/output is primary: shell, vim, tmux, git, SSH to another host and arbitrary CLI programs must remain possible. Coding-agent awareness is optional and cannot become a dependency of terminal access.

The owner deliberately runs agents with broad local permissions. Per-command mobile approval prompts are unwanted. This makes app access and SSH identity valuable security boundaries, but does not justify redefining the user's accepted local authority.

## Current outcome

WORKING PHYSICAL-IPHONE SSH/TMUX SPIKE.

The owner has run commands, attached the existing tmux shell, recovered the same session and confirmed recovery without another Face ID prompt. Instrumented traces independently show automatic foreground recovery and recovery after app-authentication expiry. This is meaningful feasibility evidence, not full daily-use acceptance.

## Recommended architecture

```text
SwiftUI/UIKit iPhone app
  -> community GhosttyTerminal / patched libghostty / Metal
  -> Apple SwiftNIO SSH
  -> official Tailscale app's OS VPN
  -> ordinary macOS OpenSSH
  -> tmux
  -> shell / arbitrary CLI / eventually coding agents

Mac terminal or iTerm2 -> the same tmux session
```

There is no MoshDeck backend, account, database, relay, companion daemon or agent protocol. Tailscale has its own coordination service and can relay encrypted traffic through DERP; no claim of always-direct peer connectivity is made.

| Question | Decision | Confidence |
| --- | --- | --- |
| Terminal engine | Pinned community GhosttyTerminal for the spike; broader fidelity and maintenance gates remain | Medium |
| Initial transport | SwiftNIO SSH to ordinary macOS OpenSSH | Medium |
| Tailscale | Official apps, ordinary sockets and MagicDNS | High |
| Mosh | Defer until measured SSH deficiencies justify it | Medium |
| tmux | Central persistence primitive; saved attach helper | High |
| iTerm2 API | None; independent tmux attachment | High |
| Mac companion/backend | None | High |
| Agent APIs/notifications | Deferred | High |
| Product name | MoshDeck is provisional; avoid committing to a Mosh-specific public identity yet | Medium |

Confidence is architectural fit, not a complete compatibility or security certification.

## Technology and research conclusions

Upstream Ghostty's full application embedding path is not simply an iOS renderer. The spike uses the pinned Lakr233 community frontend and its patched libghostty/UIKit/Metal integration. VT parsing/state, renderer, platform view and remote I/O are separate concerns. The community fork and prebuilt artifact are maintenance/supply-chain risks. SwiftTerm is a fallback if device fidelity or maintenance fails; no replacement is justified by the observed connection failures.

Core dependencies are pinned: SwiftNIO SSH 0.15.0, SwiftNIO 2.102.0, Swift Crypto 4.5.2. The controlled Ed25519/OpenSSH subset works. This is not broad SSH-config, jump-host, key-import or keyboard-interactive compatibility. Software Ed25519 is not Secure Enclave-backed.

Research considered libssh2, libssh, SwiftNIO SSH, NMSSH, Citadel, Mosh, terminal alternatives, Tailscale distributions and existing clients. Ordinary macOS sshd over Tailscale avoids the different deployment requirements of Tailscale SSH. Mosh may improve prediction/roaming, but cannot prevent iOS suspension. tmux keeps processes alive independently of either transport.

Existing apps, especially Blink and other serious mobile terminals, remain credible alternatives. Personal differentiation is terminal fidelity, a prompt composer, keyboard ergonomics and tmux continuity—not another cloud service. Dependency license and upstream references are in the repository research; patched/prebuilt artifact provenance and complete distribution notices remain release gates.

## Implemented behavior

- One active remote terminal, saved host/user/port/trust/session profile, device-only Keychain identity and draft storage.
- Strict supplied host-key verification before public-key authentication; no trust-all fallback.
- Explicit Connect/Cancel/status/failure, Copy Diagnostics, public-key Copy/Share.
- Synthetic Fixture and real SSH tabs; auth-only, echo/no-PTY, clean shell, normal shell and tmux diagnostic modes.
- UIKit terminal input, PTY resize, bounded input/output, scrollback, Esc/Ctrl-C/Ctrl-B, native multiline composer and explicit paste/Enter intent.
- Persistent Hide Keyboard, Expand terminal and Restore controls. Expansion changes presentation, not connection ownership.
- Opaque inactive-scene privacy cover, remote OSC clipboard reads/writes and URL handling disabled, no terminal analytics/transcript logging.

Not implemented as a finished product: host management polish, session picker, multiple simultaneous terminal tabs, comprehensive mobile key mappings, notifications, agent awareness, repository/file UI or iPad polish.

## Lifecycle and diagnostics

App lock and SSH connection are separate models. Cold launch starts locked. Authenticated foreground use has no expiry. First inactivity starts a five-minute grace period; background does not extend it. Foreground entry checks the deadline before restoring access, including after suspension. Connect/retry/reconnect never invoke Face ID. Explicit Lock or expired background grace closes SSH and hides terminal/composer content. The foreground no-expiry behavior has a 28-minute trace; a separate 6m56s screen-lock/authentication/recovery test passed.

Connection states: idle, starting(stage), connected, reconnecting, disconnected, cancelled, failed. Stages cover preparation, terminal initialization, grouped DNS/TCP opening, SSH negotiation, host verification, authentication, session channel, PTY, shell/tmux startup and awaiting output. DNS success is not independently observed.

Connected requires remote shell/exec acceptance plus terminal output. Output could be a login banner; it does not prove a specific application is ready. A ten-second post-acceptance output deadline handles a silent startup.

Each attempt has an ID. Old callbacks cannot mutate a new attempt. First fatal error wins; cleanup cannot replace it. UI state is MainActor-isolated; SSH wraps NIO event-loop operations. Ordered callbacks pass through an AsyncStream.

Backgrounding closes transport deliberately. The last screen/draft remains locally, with input disabled during recovery. Reconnect uses attach-only tmux semantics and cannot silently create a replacement session. A new successful renderer replaces the old one; local scrollback is not merged across reconnect, and tmux copy mode remains the remote-history source.

Initial failures require manual retry. Transient runtime failures have bounded foreground retries at 0, 1, 2, 5 and 10 seconds. Host mismatch, rejected authentication, malformed configuration and deterministic startup failures do not loop. Foreground resume reconnects when unlocked and a session is still desired.

Diagnostics contain stages, safe error categories, timestamps, attempt IDs and public-key fingerprints—not terminal bytes, private keys, commands or pasted prompts. Recent attempts are bounded. New events identify scene transitions, unlock request/success, lock reason and manual/foreground/retry connection triggers.

## Bugs found and fixed

| Problem | Evidence and fix |
| --- | --- |
| Public-key long press did nothing | Explicit Copy/Share enabled authorization |
| Debug username/host-key prefill empty | Missing Swift DEBUG condition fixed; physical field test passed |
| Face ID repeated in connection flow | App lock separated from transport |
| Startup cause hidden by disconnect | Attempt ownership and first-error preservation |
| Cancel stalled until startup timeout | NIOSSH consumed channelInactive; observing parent closeFuture fixed reproduced test |
| Diagnostic picker selected the wrong mode | Intent routing centralized and unit tested |
| Keyboard concealed tabs | Persistent dismissal and expand/restore; physical test passed |
| TCP shutdown classified permanent | Exact NIOSSH TCP-shutdown classification corrected; automatic outage-to-5G recovery observed |
| Recovery reused an old platform view | Explicit terminal-state view identity; owner reported improved recovery display |
| Sticky modifiers survived focus loss | Reproduced in real wrapper fixture; adapter resets modifiers on resignation; simulator pass, physical pending |
| SSH test waited for obsolete failure wording | Stable accessibility connection state; simulator lock-state assertion passed |
| Local OpenSSH tests hung during destruction | Sampled Foundation waitUntilExit stall; explicit fixture cleanup; three repeated runs left no fixture directories |

The original silent Connect loop lacked a retained trace. Several fixes preceded success, so no exclusive historical root cause is claimed. The close-signal/cancellation defect was independently reproduced.

## Empirical evidence

Physical device: iPhone 15 Pro Max, iOS 26.6. Xcode 26.6. Mac uses ordinary OpenSSH and a disposable tmux shell; no agent workload was started. The first table retains historical spike observations; the current-policy rows below have separate evidence.

| Check | Result and scope |
| --- | --- |
| Phone SSH authentication/PTY/shell | Passed; first output 4.47 s in initial sample, 2.06 s in later clean-shell sample |
| Actual command use | Owner confirmed commands worked; private terminal text not collected |
| Phone tmux attach | Passed, 1.89 s; original pane/shell PID retained |
| Concurrent Mac PTY + phone | Both clients attached; 120x40 Mac client resized pane, closing it restored phone dimensions; same shell |
| Background recovery | 116.288 s measured background-to-active interval; automatic foreground reconnect reached output in 2.34 s with no new unlock |
| App-grace expiry/authentication | Expiry logged; owner unlocked; automatic reattachment in 2.61 s; same shell |
| Wi-Fi-off/cellular test | Owner reported success; captured connection survived inactive/active events; interface choice not independently instrumented |
| Saved profile after new build/relaunch | Successful connection without host/user/trust/session launch overrides corroborates restoration |
| Keyboard dismissal/expand/restore | Physical fixture UI test passed |
| Parser/input fixture, app-lock gate, 30 s composer retention | Physical tests passed; synthetic scope, not full remote application acceptance |

Timing values are individual attempt-start-to-output samples, not p95 measurements, keystroke latency or general network guarantees. The local Mac concurrent client was a PTY, not an iTerm2 UI acceptance run.

Current implementation evidence:

| Check | Result and scope |
| --- | --- |
| Foreground no-expiry | 28m 1.31s connected-to-inactive trace plus owner report; no intervening relock/disconnect |
| Screen lock >=5 min | 6m56s measured background, required authentication, automatic reattach in 2.495s; same shell PID 89665 |
| Full outage | Owner confirmed Airplane Mode then 5G; automatic recovery, no repeat auth, same PID |
| Outage timing | 38.41s from first foreground, but restoration time unknown; successful attempt took 5.572s |
| Composer | Owner confirmed basic use after recovery; individual large-size/copy/relaunch cases remain pending |
| Current core suite | 32 reported tests, including one opt-in skip; passing full run in 4.270s |
| Repeated local integration | Three further OpenSSH-suite passes, each with no newly orphaned fixture directories |
| New modifier fix | Reproduced failure before fix; parser/input and keyboard dismissal/expansion simulator tests passed after fix |
| Dependency reproduction | Core source artifact built; isolated iOS consumer built; two simulator checks passed; self-built artifact not installed |
| Release build | Unsigned arm64 build passed; app regular files 18,165,878 bytes; not physical memory or App Store download size |

The core suite includes host rejection, first failure, stale callbacks, cancellation, lock transitions, input generation isolation, missing tmux attach without replacement, PTY resize, Ctrl-C, exact 1 MiB output and 1/10/50 KB synthetic Unicode byte preservation. These local tests do not fill the phone matrix.

## Remaining risks and acceptance gaps

1. Separate 20/60-minute lock recovery, both controlled network directions, termination, Mac unavailable and explicit Lock under the current policy. Full-outage recovery passed, but offline-input/draft assertions need physical confirmation.
2. Real CLI/agent fidelity, actual iTerm2 handoff, Unicode/IME/copy, hardware keyboard, VoiceOver, large composer prompts and sustained output/interrupt behavior.
3. Device typing/render latency, memory/CPU/battery, sustained dogfood and an existing-client baseline where available.
4. Engineering controls remain visible; one saved profile/identity model; viewport-only native copy and local scrollback replacement on reattach. Native Copy is not explicitly local-only.
5. Distribution review: linked LGPL libintl in Release, MPL z2d source dependency, remaining glyph attribution and final source/relinking obligations. Many exact notices and source-reproduction records are now bundled; that is not blanket distribution clearance.

No 20/60-minute pass is inferred from elapsed background time, and no coding-agent continuity pass is inferred from a shell session.

## Recommended next work and scope

Keep the architecture and finish the reliability/terminal matrix before expanding product scope. Highest-value immediate step: complete the pending long-lock phone recovery observation before replacing the installed build. Reopen, authenticate if prompted, observe automatic versus manual recovery, run `echo $$` (baseline 89665), and check draft retention. Then test the newer font/modifier build and continue the separate acceptance rows. A disposable CLI/coding workspace can be prepared with `Spike/scripts/prepare-terminal-acceptance.py`; its three baseline tests passed, but no agent was launched.

Daily MVP: saved host, trusted key auth, correct terminal, usable mobile keys/composer, tmux attachment, clear lifecycle/recovery and privacy. Add session browsing or multiple terminals only after daily use demonstrates the need. Exclude backend/signup, companion, Mosh implementation, agent APIs, notifications, widgets, file browser and code editor for now.

## Repository and handoff state

Repository: chenrui333/moshdeck, branch `main`. Checkpoint before this documentation refresh: `e5899e11c0b7363b9dd9ff4e88bc08f0a9e09a25`, clean working tree. The successful spike and subsequent changes are preserved in scoped DCO-signed local commits; nothing was pushed. The installed phone code remains the `5582b2a` view-identity recovery fix. Newer code includes explicit JetBrains Mono selection (`f9c1f4b`), stable automation status (`2bfb810`) and sticky-modifier reset (`012e1b3`); these built but were not installed during the pending lock test.

Do not reinstall or replace the current tmux shell merely to refresh metadata. No live build process remains from this checkpoint. Device tests require owner interaction; an unanswered question is not a passing result. See [MVP](../mvp.md), [phone steps](phone-test-steps.md), [terminal matrix](terminal-compatibility.md), and [performance](performance.md) for the remaining gates.

Review entry points: [architecture](../architecture.md), [product](../product-direction.md), [security](../security.md), [lifecycle](connection-lifecycle.md), [physical evidence](physical-device-connection-debug.md), [spike plan](../spike-plan.md), and [licenses](licenses.md). Implementation: Sources/MoshDeckCore/ConnectionLifecycle.swift, SSHConnection.swift, SessionIntent.swift; Spike/App/RemoteTerminal.swift and MoshDeckSpikeApp.swift; Tests/MoshDeckCoreTests and Spike/UITests.
