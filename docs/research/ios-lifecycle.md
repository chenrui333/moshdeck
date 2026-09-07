# iOS lifecycle and recovery

Design as of 2026-09-06; no physical-device results claimed. Apple permits limited background completion, not an indefinitely running generic terminal. [UIKit background execution](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time) explains the short transition window, expiration handler and obligation to end background tasks.

Newer [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados) supports user-initiated finite work, progress and cancellation, including network use. It is not a guarantee for an idle remote-terminal subscription. The actual coding job runs on the Mac, so MoshDeck has no local long-running work to justify abusing this API. Background URLSession transfers also do not maintain arbitrary SSH sockets.

## State and ownership

A main-actor session coordinator owns visible state and a monotonically increasing connection generation. A transport owns its socket/channel on one event loop. The terminal owns its parser/grid; the Mac owns the durable tmux session. Paths becoming available are a hint to attempt connectivity, not proof the host or SSH channel is live.

`Locked -> Disconnected -> Connecting -> Verifying -> Authenticating -> Attaching -> Live`.

On failure: `Live -> Reconnecting` with input disabled and last display marked stale. Host-key mismatch or auth rejection is a terminal failure until user action, not an endless retry. Every callback carries a generation so a late connect/read/close from a previous attempt cannot affect a new session.

For the first spike choose **deterministic close on entering background**, retain only an in-memory stale display, and reconnect on foreground after app unlock. Save host/session identifiers and protected draft text, cancel pending writes, stop rendering, and close the transport without sending Ctrl-C, shell `exit`, or `tmux kill-session`. This intentionally establishes a simple reliable recovery baseline. After measuring reconnect costs, a short bounded grace window may retain a socket opportunistically; persistence is never assumed.

While foregrounded, use finite connect/auth/PTY timeouts, an SSH-level liveness response and bounded retry backoff (for example 0, 1, 2, 4 seconds, capped at 15 with jitter). Suspend retry timers while backgrounded or locked. Give the owner immediate Disconnect/Retry controls. Do not send visible text or shell commands as keepalives. Initial timer values are experiment settings, not established performance facts.

## Required scenarios

| Case | Required behavior | What cannot be promised |
| --- | --- | --- |
| A. Switch apps for 30 seconds | Hide sensitive view immediately; background closes spike connection; foreground unlock and reattach same tmux session | That iOS gives 30 seconds runtime or keeps TCP alive |
| B. Lock five minutes | Key material inaccessible under selected protection; restore host/draft, reconnect and redraw after unlock | Uninterrupted network or background rendering |
| C. Lock twenty minutes | Same as B; server task continues if Mac remains awake | Last local screen is current; all missing output is in phone scrollback |
| Additional: lock/idle one hour | Same recovery contract; measure Mac policy/SSH timeout interactions | A long-lived client process/socket |
| D. iOS kills app | Cold launch reads protected profile/draft only, validates host and attaches saved tmux target | Old parser/connection memory survives; termination callback runs |
| E. Wi-Fi disappears, cellular takes over | Pause input on detected failure; retain surviving verified connection only while known responsive; reconnect when needed | NWPathMonitor proves tailnet/host reachability |
| F. Airplane mode two minutes | Display Disconnected/stale, no queued sends; reconnect after path returns and reattach | Automatic replay of typed commands is safe |

For foreground idle of 5/20/60 minutes, liveness checks may detect a dropped connection; screen lock then follows B/C. Radio/captive portal/VPN failures should be distinguished from host rejection where evidence permits, without exposing sensitive diagnostics.

## Input and redraw invariants

- Never queue raw input while disconnected or locked. A user may keep editing a local composer draft.
- TCP write success is not proof the remote application processed a prompt. A failure after partial send is ambiguous; retain the draft and require explicit retry. Never claim exactly-once command delivery.
- Paste + Enter is one ordered operation scoped to a connection generation. Do not send Enter after reconnect or before an asynchronous paste decision completes.
- Reconnecting uses a fresh renderer, PTY with current dimensions, and attach to the existing tmux session. View-only stale content must not generate terminal replies.
- tmux redraw restores visible state. Historical output remains in tmux history subject to its limit; use copy mode for history missed while disconnected. A full byte-for-byte transcript is not an MVP feature.
- An absent tmux session is shown as missing. Do not silently recreate it and claim the old task survived. Initial Create/Attach can use `new-session -A`; reconnect must use attach-only.

## Mac lifecycle is a separate gate

Remote tasks must be started inside tmux, and `destroy-unattached` must remain off. Closing a phone transport should only detach its tmux client. Mac sleep, reboot, FileVault pre-login, VPN disconnection, user logout, tmux configuration hooks, or loss of power can interrupt access or work. A phone app does not fix these. Inspect host configuration; do not silently change power policy or sshd settings.

## Measurement

Use monotonic time for network-available to first interactive tmux redraw, separately recording app authentication time and SSH time. Repeat handovers and resumes with the official Tailscale app active; record direct versus relayed path when obtainable from an authorized host-side diagnostic. Measure a cold launch separately from a warm resume. Simulator lifecycle events validate coordinator behavior, not modem, lock, Keychain, or suspension behavior on an iPhone.

No fake audio, location, VoIP or VPN background entitlement. No background polling of agent logs. Live Activities and APNs are discussed in [ecosystem research](ecosystem.md) and remain outside MVP.
