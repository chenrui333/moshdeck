# Product direction

Investigation date: 2026-09-06 (America/New_York). Recommendation, not a claim of device validation. See [spike plan](spike-plan.md) and [evidence](research/spike-results.md).

## What this product is

A private iPhone terminal for resuming control of a development workspace that continues running on an awake Mac. The target user is a technical owner who deliberately gives local coding agents broad authority. The phone supplies terminal display, keyboard input, selection, and comfortable prompt composition; the Mac supplies processes, repositories, credentials, tools, and execution.

The product succeeds when leaving the desk costs no process restart and returning costs no session migration. Raw shell access must work independently of any agent. An agent dashboard is optional convenience.

## Workflow and the important correction

1. On the Mac, start or attach `tmux new-session -A -s work` in iTerm2, then launch the desired agent or shell command inside it.
2. Walk away with the Mac awake, powered, network-connected, and logged in as required by its Tailscale distribution.
3. On iPhone, connect over the official Tailscale VPN to macOS OpenSSH, allocate a PTY, and attach the same tmux session.
4. Inspect the live screen, use raw keys or the multiline composer, and disconnect when finished.
5. Attach from iTerm2 again, or continue using its existing attachment.

An arbitrary agent already running outside tmux cannot be adopted reliably by this architecture. Set up tmux before starting the long task. Session continuity means the same remote processes and tmux state, not pixel-identical terminal layout, recovery of all iTerm2 scrollback, or surviving a Mac reboot. Phone width necessarily changes full-screen layout. Sleeping the Mac pauses work and removes reachability; closing a laptop lid is not an always-on guarantee.

## Build versus use

Use Blink + Tailscale + tmux as the baseline before committing to a new daily-use app. It plausibly solves 95% of the operational need; that percentage is a product estimate, not a measured comparison. Prompt also supports SSH and Mosh. Remux already combines Ghostty, direct SSH, tmux, and a composer, with considerably more native pane/file functionality. See [ecosystem comparison](research/ecosystem.md).

The remaining reason to build is personal control over a small, predictable interface: a reliable large-prompt composer, carefully chosen keyboard behavior, explicit connection freshness, uncomplicated host trust, and tmux handoff. Ghostty fidelity is a candidate benefit, not a demonstrated advantage over existing clients. If existing apps satisfy those needs on the physical phone, stop building and keep the setup documentation.

## Smallest useful daily MVP

- Saved hosts with display name, hostname/IP, username, port, key identity, and an optional saved tmux session; ordinary shell access remains available.
- One active terminal at a time, SSH key authentication, verified host identity, reconnect, resize, bounded scrollback, selection/copy, hyperlinks with explicit opening, and accurate connection state.
- A proven terminal frontend. First evaluate the pinned community Ghostty wrapper; no custom emulator or renderer project.
- Level 1 tmux helpers: saved attach targets and optional text session listing, without a native window/pane model.
- Multiline iOS composer with draft retention, dictation through the system keyboard, paste, and separate Paste / Paste + Enter actions.
- Esc, sticky Ctrl/Alt, Tab, arrows, Ctrl-C, and a configurable tmux prefix. Hardware keyboard semantics pass through the engine.
- Keychain, host-key change blocking, biometric app lock with a reasonable grace period, and app-switcher privacy.

Start with iOS 18 as a project floor, SwiftUI for screens, and UIKit for the terminal and text input. This is a product choice, not a dependency minimum. Use Dynamic Type for controls/composer and VoiceOver labels for every action; terminal content accessibility requires separate testing. No promise that a GPU grid is automatically accessible.

## Interaction contract

The top bar always identifies host and session. States are Connecting, Verifying host, Authenticating, Attaching, Live, Reconnecting, Disconnected, and Locked. A cached terminal is labelled stale and cannot accept input. Never show a green host dot based only on cached metadata or network-path availability. Session counts require a successful fresh query.

Raw keyboard input bypasses the composer. Key presses use the engine's key encoder; paste uses its paste API. Do not hardcode arrow escape sequences or conflate Enter with pasted text. Sticky modifiers clear on use, disconnect, focus change, and lock. Repeatable arrows stop on touch cancellation. Expose Ctrl-D/Ctrl-Z in the expanded row; do not put destructive session-kill controls next to Ctrl-C. Device Command/Globe shortcuts may be intercepted by iOS; test real keyboards instead of promising full passthrough.

Composer dismissal retains the draft. Paste does not append a key press. Paste + Enter appends an encoded Enter only after paste completion on the same live connection. An optional Ctrl-J action sends that actual control key, not a guessed agent-specific submit command. Never resend after an ambiguous network failure. Keep the draft for explicit retry and explain that partial delivery is possible. Require inspection for embedded control characters and multiline paste when bracketed paste is unavailable; even a paste without an appended Enter may execute embedded newlines in a shell. Bracketed paste reduces accidents but is not a security boundary against a hostile remote program.

## Phases and evidence gates

0. Compare an existing client and run the technical spike. Prove terminal rendering, SSH PTY I/O, tmux continuity, input correctness, and lifecycle behavior before polishing screens.
1. Deliver the smallest daily MVP above after the device matrix passes.
2. Add only observed needs: session picker if manual targets are cumbersome; customizable keys if recurring chords are painful; multiple connections/iPad if actually used; Mosh only if measured SSH disruption materially hurts mobility or latency.
3. Optional agent metadata with `unknown` as a valid state. Add no foundational agent dependency.
4. Optional notifications after a concrete event source and privacy-preserving delivery path have been demonstrated valuable.

## Non-goals

No local agent execution, command approval system, Mosh implementation in the initial MVP, MoshDeck accounts/cloud/relay, embedded VPN, mandatory Mac daemon, iTerm2 API, tmux control mode, repository/file browser, code/diff editor, GitHub client, Kubernetes/Terraform UI, automatic session migration, terminal transcript sync, analytics containing terminal data, push, or Live Activities.

## Name

Keep MoshDeck only as the repository's working name during the spike. Choose a transport-neutral public name before release. Do not imply Mosh support or add Mosh to justify the name. No repository rename is performed by this investigation.
