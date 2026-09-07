# Existing clients and additive agent features

Observed 2026-09-06. Feature availability is based on source/vendor documentation, not hands-on phone comparisons. No purchases, subscriptions or TestFlight enrollment were performed.

## Existing clients

| Product | Existing fit | Mosh / tmux / keyboard | Source and reuse |
| --- | --- | --- | --- |
| [Blink Shell](https://docs.blink.sh/) | Serious iOS remote terminal; use as initial control experiment | SSH/Mosh, ordinary tmux, Smart Keys and hardware keyboard options | [GPL-3.0 source](https://github.com/blinksh/blink); inspect pinned source before reuse. hterm/web terminal and native transport heritage, libssh2/libmoshios and crypto frameworks in build docs |
| [Prompt 3](https://www.panic.com/prompt/) | Native terminal with SSH and persistent transport options | Vendor advertises Mosh/Eternal Terminal, customizable keyboard features, jump hosts; ordinary tmux works as remote program | Proprietary application, no source reuse; good second baseline |
| [Termius](https://apps.apple.com/us/app/termius-modern-ssh-client/id549039908) | SSH host management, mobile terminal and snippets; optional broader sync/team product | iOS listing advertises SSH and Mosh; tmux is a remote program | Proprietary app; do not assume advertised features imply a reusable implementation |
| [Secure ShellFish](https://secureshellfish.app/) | iOS/Mac SSH terminal and strong Files integration | Ordinary tmux and snippets/control-key sequences; Mosh not established by reviewed primary docs | Proprietary app; SwiftTerm upstream names it as a consumer |
| [WebSSH](https://webssh.net/) | SSH, SFTP, tunnels and host management | Ordinary tmux, terminal keyboard; Mosh not established by reviewed primary docs | App source reuse not established; public support tracker is not a code license |
| [Remux](https://github.com/h3nock/remux/tree/d098ec6ae5165116e32621b265ec934b087fb5c0) | Very close overlap: Ghostty, direct SSH, Keychain, tmux, composer/dictation, shortcuts | Native windows/panes via tmux control mode; attachments/previews broaden scope | MIT; own Ghostty and Citadel forks. Useful implementation reference; stability/device behavior still unverified here |
| [SwiftTermApp](https://github.com/migueldeicaza/SwiftTermApp) / [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Open source iOS SSH frontend example and terminal component | Engine/UI examples; scope/version must be checked before adopting a whole app | SwiftTerm MIT, mature alternative to patching Ghostty |

All ordinary TCP SSH clients can in principle connect to a tailnet address through the official OS VPN. This is protocol compatibility, not a claim that each app has native Tailscale discovery/authentication or has passed our real-device test. Mosh clients also need reachable UDP and a compatible server.

Building MoshDeck is optional. A private app need not invent differentiation, but cannot justify its maintenance cost with terminal access alone. Compare a 500-word prompt, Ctrl-C/Escape, reconnect after 20-minute lock, Wi-Fi/cellular roaming, full-screen apps and Mac handoff in Blink and Remux. If those feel right, use an existing app. Otherwise implement only the observed missing interaction. No code from these apps has been copied during research.

## Codex awareness: stable access first

The local installed CLI reports `0.153.4`. Its help exposes `app-server`, `remote-control`, `agents`, `queue`, `resume`, and `exec`; the first two are still labelled experimental locally. This is evidence against the stale assumption that Codex has no structured control surfaces, but it does not make those surfaces necessary for a terminal.

Current official documentation describes [App Server](https://developers.openai.com/codex/app-server/) JSON-RPC thread/turn events and structured control, [noninteractive execution](https://developers.openai.com/codex/noninteractive/) JSON output, and [hooks](https://developers.openai.com/codex/hooks/). These are different integration modes:

- `exec --json` describes a noninteractive run. It is not a way to attach a renderer to an existing arbitrary terminal TUI.
- App Server can support a separate structured client and managed threads; it is not a transparent vim/shell/SSH proxy.
- Hooks can report lifecycle events for later notifications, but must be opt-in and version-qualified. Installing hooks changes the Mac's agent behavior and is outside the initial spike.
- MCP exposes tools/resources; it is not a general terminal screen/input protocol.
- Private rollout files, SQLite state, logs and process command lines are not stable APIs and can contain sensitive prompts/credentials. Do not scrape them for the MVP.

Cheap future metadata: tmux `pane_current_command`, `pane_current_path`, IDs, window names and activity timestamps. A foreground process named `codex` does not prove running versus waiting. `ps` can inspect descendants when needed, but avoid collecting full arguments. A directory can be used for a bounded `git -C ... branch --show-current` query; do not run expensive `git status` on every refresh. A separate exec channel's `pwd` is its own shell directory, not the active pane's directory.

Any eventual `AgentSession` should tolerate `unknown`, stale metadata and missing agent adapters. Do not start building this abstraction until metadata demonstrates value. Open Terminal, Compose and raw Ctrl-C need no agent integration.

## Notifications and Live Activities

No notifications in MVP. A future Mac process or hook could send a minimal opaque host/session identifier and generic event type directly to APNs, keeping terminal content out of notifications. This still requires notification permission, device-token registration/rotation and APNs provider credentials, and the Mac must be reachable/running. It may avoid a custom cloud service but does not avoid APNs or Mac-side software. [Apple token-based APNs connections](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns).

A Live Activity can show elapsed time from a known start date without claiming continued progress. Actual completion/waiting changes require the app to get runtime or receive ActivityKit pushes. It is not a continuously running network client. It risks exposing repository names on a lock screen and gives little benefit before a reliable event source exists. [Apple Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).
