# Daily-use MVP

Status: implementation in progress; internal TestFlight beta available September 12, 2026. The owner accepted the physical feasibility spike. Its code and evidence are preserved in local commits 44a114c, 938b1cc and d317f1d. Version 0.0.1 (1) is in internal beta testing for the owner; this is not completion of daily-use acceptance. See [TestFlight status](testflight.md) and the [beta setup website](../site/README.md). This document defines the new implementation phase; historical spike reports retain their original observations.

## Supported workflow

One active phone terminal controls an awake Mac through ordinary SSH over the official Tailscale VPN. tmux retains processes and the Mac/iPhone clients attach independently. The accepted frontend is pinned GhosttyTerminal with patched libghostty; transport is SwiftNIO SSH. Actual Codex terminal interaction is required acceptance, not a custom integration.

Prerequisites: official Tailscale installed and signed in on both devices; macOS Remote Login; a dedicated authorized phone Ed25519 key; an out-of-band verified Mac host public key; tmux installed and an existing session. Remote Management and remote scripting are not prerequisites. The app does not embed a VPN or expose public ports. Configure the MagicDNS hostname as an ordinary SSH hostname, port 22 and the actual Mac username.

On the Mac, create the workspace before starting persistent work:

```sh
tmux new-session -A -s work
```

Save `work` and the actual tmux executable path in the app. Recovery attaches exactly to the existing session; it must not silently replace a lost session. A Mac reboot or terminated tmux server does not preserve work. Ordinary non-tmux shells do not have the same persistence guarantee.

## Authentication and privacy

Cold launch and explicit Lock require device-owner authentication. Authenticated foreground use has no timeout. First inactivity starts five minutes of grace; backgrounding does not extend it. Return within grace requires no new authentication. Return at/after expiry requires authentication before remote control; desired tmux attachment can then recover automatically. Explicit Disconnect clears session desire. Inactive scenes and locked composer content are concealed.

Phone key, profile and draft are device-only Keychain items. No password persistence, private-key export, transcript/prompt logging, remote OSC clipboard access or automatic remote URL opening. Host-key mismatch always blocks. Software Ed25519 is not Secure Enclave-backed. No sync or remote service exists.

## Narrow SSH scope

Ed25519 identity, supplied known host key, macOS OpenSSH, hostname/IP over Tailscale and interactive PTY. Password/keyboard-interactive, agent forwarding, arbitrary SSH config, jump hosts, SCP/SFTP and broad key-import compatibility are unsupported. Never accept an arbitrary host key to make setup succeed.

## Implementation milestones

| Milestone | Current state | Acceptance |
| --- | --- | --- |
| Preserve spike | Complete: three scoped DCO-signed local commits; baseline tests/build passed | Recoverable Git snapshot, no push |
| Foreground/background app lock | Code/tests complete; 6m56s physical lock recovery and 28m foreground-no-expiry trace passed | No active timeout; short/long absence and explicit Lock correct |
| Network reliability | Airplane Mode → 5G automatic recovery and timed lock passed; remaining matrix pending | Same session after outage, both network directions, process kill and 5/20/60-minute locks |
| Terminal fidelity | Synthetic parser/input and shell/tmux evidence; broad app checks pending | Actual CLI and Codex control without major blockers |
| Input UX | Spike composer/keys/dismissal retained; further hardening pending | Modifiers, large paste, Unicode and no offline replay |
| Performance | Connection/recovery samples and unsigned Release size recorded; device resources pending | Several current-device samples and meaningful resource observation |
| Security/provenance | Pinned source preparation, consumer/simulator checks, gettext-free Release linkage and notice-inclusive distribution export passed; Apple accepted the internal beta. Physical qualification of this artifact and ongoing dependency review remain | No known beta-blocking defect; reproducible dependency evidence |
| Product cleanup | Compact Release terminal/header and keyboard accessory implemented; physical layout acceptance pending | Minimal profiles, terminal, composer, details and lock |
| Codex dogfood | Not performed | Meaningful phone-only work interval and actual iTerm2 handoff |

## Known limitations

The installed/debug harness name and bundle identity remain stable to preserve the authorized Keychain identity. Release now opens the remote terminal surface directly; Fixture navigation and authentication/echo probes are Debug-only. The compact header, tmux menu and single keyboard accessory are implemented, with physical layout acceptance pending. Only one saved-profile model exists so far; multiple profiles and identity selection are not yet complete. Local renderer scrollback is replaced on successful reattach; remote tmux history remains available through copy mode. Input delivered before an undetected network loss may have ambiguous delivery; it is never automatically resent on a new connection.

Separate 20/60-minute screen locks, controlled network directions, process termination, outage input/draft assertions, actual iTerm2 UI, real Codex, broad full-screen/IME/hardware-keyboard and device-resource tests remain gates. A 6m56s screen-lock test and Airplane Mode-to-5G recovery passed; neither fills these other rows. See [physical evidence](research/physical-device-connection-debug.md).

## Shared-process acceptance is a required MVP gate

Actual iTerm2 and a physical iPhone must simultaneously attach to the same existing tmux session/pane and control the same running Codex process. Verify input in both directions, disconnect the phone while the Mac remains usable, detach the Mac while the phone remains usable, then reattach both and compare the original shell and Codex PIDs. These are required acceptance checks, not a future feature and not satisfied by generic PTY concurrency tests. Current results are in [physical evidence](research/physical-device-connection-debug.md).

Start with `tmux new-session -A -s work` in iTerm2 and launch Codex inside it. A Codex process already running in an ordinary non-tmux shell cannot be adopted automatically. The phone must use the same session and pane; separate panes normally have different processes.

## Multiple sessions in this beta

The Mac can host multiple tmux sessions, windows and panes. MoshDeck currently has one saved profile and one active connection. tmux's native session picker (Ctrl-B, then S) can switch the current client, but that switch does not update MoshDeck's saved target: after interruption, reconnect attaches to the session named in the profile. For predictable recovery, explicitly disconnect and change the saved Session field before connecting to another workspace. Switching between at least two tmux sessions from the physical phone is an MVP acceptance gate; the existing Ctrl-B control and normal tmux picker are sufficient. The owner subsequently requested native browsing: tmux → Switch Session now opens a native side panel. Choosing a row explicitly reattaches to that existing session and updates the saved reconnect target. This differs from manual switching inside tmux. Physical acceptance of the panel remains pending; multiple simultaneous app terminals remain post-MVP.

## Deferred scope

No Mosh, backend, signup, companion, notifications, agent APIs/dashboard, files/editor/Git UI, SCP/SFTP browser, multiple simultaneous terminals, plugins, themes marketplace, iCloud sync or analytics SDK. Architecture changes require new acceptance evidence, not preference for novelty.

## Typography

The terminal explicitly requests JetBrains Mono at the current 14-point default. The pinned Ghostty core embeds variable regular/italic JetBrains Mono faces and retains fallback handling for other glyphs. Original app controls and the native composer use iOS fonts; the selection sheet uses a Dynamic Type-scaled system monospaced font. No font picker is included. The JetBrains Mono SIL Open Font License notice is bundled in `Spike/App/Notices/JetBrainsMono-OFL.txt`. This is one dependency notice, not completion of the full third-party notice audit.

## Normal terminal surface

Release uses a compact host/status header with tmux actions, Compose and overflow. The saved **Reconnect target** is shown in the tmux menu/details, not presented as an observed live session. Switch Session opens the native session side panel. Its terminal-picker fallback sends the default Ctrl-B, then lowercase s sequence; custom tmux prefixes remain manual. The header exposes Show Keyboard when terminal focus is dismissed. A single keyboard accessory provides Esc, sticky Ctrl, Tab, arrows and Hide Keyboard. Ctrl+C is available by arming Ctrl and typing c.

Connection Details, profile editing, sanitized diagnostics, Disconnect and Lock remain separate overflow actions. Disconnect first to edit the profile. Compose retains native multiline editing and the existing explicit paste/separate-Enter flow; sending is disabled offline. Reconnect keeps the last terminal visible under compact progress/failure controls. See [layout implementation and physical acceptance](research/layout.md) for implemented versus verified behavior. No native terminal tabs or session model were added.
