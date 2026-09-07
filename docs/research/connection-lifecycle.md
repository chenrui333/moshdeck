# Connection lifecycle and diagnostics

Status: daily-use MVP implementation, 2026-09-07. Architecture remains Ghostty + SSH over official Tailscale + ordinary Mac OpenSSH + tmux. Actual Codex terminal use is an acceptance workload; agent APIs and additional services remain out of scope.

## Ownership and states

`AppLockPolicy` and `ConnectionLifecycle` are independent value models in MoshDeckCore. `RemoteTerminalModel` is MainActor-isolated and orchestrates them. `SSHConnection` is an actor wrapping NIO event-loop-confined handlers. Ghostty receives ordered bytes and emits input/resize callbacks; it does not navigate or choose retries.

App lock states: locked, unlocking, unlocked(until: optional deadline), unlockFailed. An absent deadline means authenticated foreground access. Connection states: idle, starting(stage), connected, reconnecting(retry index), disconnected, cancelled, failed(structured failure). UI progress and input availability derive from these states; they are not independently toggled connection booleans.

Each explicit or automatic attempt gets a UUID. Event acceptance is invalidated on cancellation/background/disconnect without changing the historical attempt UUID. A new attempt gets a new UUID. Stale events cannot change the current attempt. Ordered SSH events travel through one AsyncStream consumer on MainActor. Terminal-output callbacks never export the bytes as diagnostics. Scene transitions, unlock request/success, lock reason and connect trigger are also recorded as local categories so foreground recovery can be distinguished from manual Connect and retry timers.

## Observable stages and limits

| Stage | Evidence |
| --- | --- |
| preparation | Profile validation and Keychain identity load |
| terminal | Creation/configuration of the Ghostty candidate frontend |
| openingTransport | NIO bootstrap DNS/address selection/TCP operation begins |
| negotiatingSSH | TCP channel activates; SSH handshake begins |
| hostVerification | NIOSSH supplies the public host key to the pin-verification delegate |
| authentication | Public-key authentication delegate is invoked |
| sessionChannel | NIOSSH UserAuthSuccessEvent proves authentication succeeded |
| pty | Session channel activates and PTY request is sent; success reply is recorded separately |
| shell or tmux | Shell/exec request is sent; success reply is recorded separately |
| awaitingOutput | Remote shell/exec request was accepted |
| connected | Remote request accepted **and** at least one terminal-output packet received |

DNS and TCP are deliberately grouped because the current bootstrap adapter does not separately observe successful DNS completion. It does not claim independent network reachability from an NWPath status. `openingTransport` errors retain safe library type/numeric codes. The parent closeFuture supplies closure because NIOSSHHandler consumes channelInactive instead of forwarding it to downstream handlers. Host verification never silently trusts a changed key.

Connected is evidence of a launched remote interactive channel, not a guarantee that every shell startup script or agent is ready. No application-specific prompt matching is used. First output may be a login banner. A ten-second no-output deadline after remote acceptance reports `awaitingOutput`; silent-shell behavior must be evaluated rather than disguised as success.

Diagnostic modes isolate authentication only (no channel/PTY), fixed echo exec (no PTY), clean `zsh -f` with PTY, and normal login shell with PTY. tmux is a separate toggle. The fixed echo test reports exit status; transport component tests additionally assert the exact synthetic marker. No arbitrary remote stderr/transcript is copied into diagnostics.

## Root error and runtime loss

`ConnectionFailure` contains stage, safe code and retryability. Attempt UUID/timestamp belong to the bounded attempt timeline. The first fatal failure wins. Later close/errors append context and cannot replace it. Startup close alone does not become a generic UI failure: the pending transport startup promise supplies the first typed error. Runtime closure after connected enters reconnecting.

NIO errors preserve their public error type without server-supplied diagnostic text. POSIX errors preserve errno; app errors preserve their semantic case; remote exit status is numeric and attributed to shell/tmux. Raw localized descriptions, command output, prompts, passwords and private keys are excluded. The loaded Ed25519 public-key fingerprint is logged to correlate Keychain identity with authorized_keys without transferring private material.

The app retains up to five previous attempt summaries plus the current bounded 100-entry timeline. Copy Diagnostics exports this sanitized data. A file-protected `Documents/connection-diagnostics.txt` permits development-device retrieval without copying the application container or Keychain. No analytics or remote logger exists.

## Unlock policy

Cold launch locks remote-control access. Explicit Unlock MoshDeck uses device-owner authentication (Face ID with system fallback). Authenticated foreground use has **no expiry**. Connect/retry/reconnect never invoke LocalAuthentication.

The first inactive transition starts a five-minute grace period. A subsequent background transition retains the same deadline. Returning before that deadline clears it and keeps the app unlocked; a new absence starts a new grace period. At or after the deadline, foreground entry locks before allowing input, even if iOS suspended the app and no timer ran. Successful authentication allows the desired session to reconnect. Explicit Lock immediately hides the terminal and closes transport while retaining session desire. The composer is covered/dismissed when app access locks.

Profile, verified host key and draft use a separate device-only, when-unlocked Keychain record. Inactive transitions save drafts before transport closes. App-switcher privacy applies immediately, independently of the grace period. Deterministic clock tests cover the policy; the changed policy still requires real-phone foreground, short absence, long absence, Face ID and composer privacy validation. Earlier timer-expiry evidence belongs to the preserved spike policy, not this implementation.

## Reconnect and cancellation

- Baseline closes transport on background instead of relying on indefinite iOS networking.
- Desired session identity, last terminal and draft remain available locally. Foreground reconnect happens only while unlocked and the desired session is active. After relock, explicit unlock may resume the desired session.
- Runtime loss retains the old terminal screen; input is disabled. A new candidate replaces it only after accepted remote startup and output. Old local scrollback remains visible during retry, but is not merged into the new terminal buffer; tmux copy mode remains the remote-history source.
- Retryable failures: transport reset/unavailability/timeouts and a bounded no-output timeout after a previously connected session. Automatic delays are 0, 1, 2, 5 and 10 seconds, maximum five attempts, foreground and unlocked only. A successful connection resets the retry budget.
- Non-retryable: host mismatch, authentication rejection, malformed profile/key, rejected PTY/request, remote command exit. These stop automatic recovery and retain the actionable failure.
- Initial startup failures require explicit retry. Runtime disconnect is distinguished from never-connected startup failure.
- Reconnect to tmux is attach-only; it never silently recreates a lost task. Explicit first creation remains optional.
- Cancel closes any registered transport channel, cancels retry/liveness tasks and invalidates event acceptance. UI returns to Ready with cancelled state, not failed. DNS work before NIO creates a channel is bounded by bootstrap timeout; no background retry continues.

## Validation and remaining gates

Deterministic tests cover root-error preservation, stale callbacks, lock grace across retry, connected evidence ordering, runtime disconnect, cancellation, and non-retryable host/auth errors. OpenSSH component tests cover actual algorithm/key interoperability, PTY/resize, input/output and host substitution. Opt-in actual-Mac tests authorize a temporary dedicated test identity under file lock and remove it in cleanup; they do not reuse or export personal private keys.

See [physical device investigation](physical-device-connection-debug.md). No backend/signup/agent work is needed to finish this gate. Full mobile reconnect, five-minute lock, path changes and cold-launch acceptance remain required before claiming a daily-use terminal.
