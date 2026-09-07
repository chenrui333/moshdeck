# MoshDeck executive review handoff

Checkpoint: September 7, 2026. Review the current engineering spike, not a shipped product. This report separates implementation, empirical results and remaining acceptance work.

## Review request

Act as a principal iOS/terminal/networking engineer and product reviewer. Challenge the design using the evidence below. Prioritize concrete correctness and mobile usability problems. Do not recommend services, frameworks or dashboards without a demonstrated workflow need.

Return:
1. Overall verdict: continue this architecture, change a specific component, or stop and use an existing app.
2. Up to five findings, ranked by severity, distinguishing observed defects from hypotheses.
3. Recommended app-lock and reconnect policy.
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

App lock and SSH connection are separate models. Cold launch starts locked. Explicit device-owner authentication grants a fixed five-minute window. Connect/retry/reconnect do not call Face ID during that window. Explicit Lock or expiry closes SSH and hides the terminal. **Expiry currently applies even while actively using the foreground terminal.** This is a known policy rough edge for review.

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

The original silent Connect loop lacked a retained trace. Several fixes preceded success, so no exclusive historical root cause is claimed. The close-signal/cancellation defect was independently reproduced.

## Empirical evidence

Physical device: iPhone 15 Pro Max, iOS 26.6. Xcode 26.6. Mac uses ordinary OpenSSH and a disposable tmux shell; no agent workload was started.

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

Latest core suite: 16 entries, 15 passed and one explicit opt-in skip. Separate actual-Mac tests passed auth-only, no-PTY echo, clean/normal shell and tmux with a temporary key removed afterward. Tests cover first failure, stale callbacks, cancellation, lock grace, host mismatch, intent routing, PTY resize, Ctrl-C and exact 1 MiB output. Latest installed build compiled successfully; formatting and whitespace checks passed. Earlier physical UI suites passed on their tested revisions; a full suite was not rerun merely for added metadata logging.

## Remaining risks and acceptance gaps

1. Continuous 5/20/60-minute screen locks, full outage/airplane mode, reverse cellular-to-Wi-Fi transition and controlled cold-launch draft recovery.
2. Broad real terminal application fidelity: vim/neovim/less/htop, coding-agent UIs, IME/CJK, hardware keyboard, VoiceOver, large prompt behavior and real output/interrupt stress.
3. Device typing/render latency, memory/CPU/battery, sustained throughput and comparable existing-client baseline.
4. Foreground five-minute relock usability, local scrollback discontinuity after reattach, and current spike-specific setup/diagnostic controls.
5. Community Ghostty upgrade burden, complete artifact provenance/license distribution review and broader SSH interoperability.

No dedicated five-minute screen-lock pass is inferred from five-minute app-auth expiry. No coding-agent continuity pass is inferred from a shell session.

## Recommended next work and scope

Keep the architecture and finish the reliability/terminal matrix before expanding product scope. Highest-value immediate test: a complete temporary network outage, then recovery to the same tmux process without offline input replay. Review lock policy before daily use; a fixed active-session timeout may be unnecessarily disruptive.

Daily MVP: saved host, trusted key auth, correct terminal, usable mobile keys/composer, tmux attachment, clear lifecycle/recovery and privacy. Add session browsing or multiple terminals only after daily use demonstrates the need. Exclude backend/signup, companion, Mosh implementation, agent APIs, notifications, widgets, file browser and code editor for now.

## Repository and handoff state

Repository: chenrui333/moshdeck. Branch main. HEAD 808927fb14ee358a92bdbab07808bf4e95fb6a0a. Research and spike work are uncommitted/unpushed; that HEAD alone does not contain this implementation. README.md is modified; package/config files, Sources, Tests, Spike and docs are untracked. Any eventual commits must have DCO sign-off and remain scoped. No push has been performed.

Review entry points: [architecture](../architecture.md), [product](../product-direction.md), [security](../security.md), [lifecycle](connection-lifecycle.md), [physical evidence](physical-device-connection-debug.md), [spike plan](../spike-plan.md), and [licenses](licenses.md). Implementation: Sources/MoshDeckCore/ConnectionLifecycle.swift, SSHConnection.swift, SessionIntent.swift; Spike/App/RemoteTerminal.swift and MoshDeckSpikeApp.swift; Tests/MoshDeckCoreTests and Spike/UITests.
