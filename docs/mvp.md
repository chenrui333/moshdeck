# Daily-use MVP

Status: implementation in progress, September 7, 2026. The owner accepted the physical feasibility spike. Its code and evidence are preserved in local commits 44a114c, 938b1cc and d317f1d. This document defines the new implementation phase; historical spike reports retain their original observations.

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
| Foreground/background app lock | Code/tests complete; 6m56s physical lock recovery passed, foreground duration owner-reported | No active timeout; short/long absence and explicit Lock correct |
| Network reliability | Airplane Mode → 5G automatic recovery and timed lock passed; remaining matrix pending | Same session after outage, both network directions, process kill and 5/20/60-minute locks |
| Terminal fidelity | Synthetic parser/input and shell/tmux evidence; broad app checks pending | Actual CLI and Codex control without major blockers |
| Input UX | Spike composer/keys/dismissal retained; further hardening pending | Modifiers, large paste, Unicode and no offline replay |
| Performance | Individual spike connection samples only | Several current-device samples and meaningful resource observation |
| Security/provenance | Source artifact, isolated iPhone build and two simulator checks passed; full notices/security audit and physical artifact qualification pending | No known beta-blocking defect; reproducible dependency evidence |
| Product cleanup | Engineering harness still visible | Minimal profiles, terminal, composer, details and lock |
| Codex dogfood | Not performed | Meaningful phone-only work interval and actual iTerm2 handoff |

## Known limitations

The installed/debug harness name and bundle identity remain stable to preserve the authorized Keychain identity. Current UI still exposes fixture/diagnostic controls. Only one saved-profile model exists so far; multiple profiles and identity selection are not yet complete. Local renderer scrollback is replaced on successful reattach; remote tmux history remains available through copy mode. Input delivered before an undetected network loss may have ambiguous delivery; it is never automatically resent on a new connection.

Longer screen-lock, complete outage, actual iTerm2 UI, real Codex, broad full-screen/IME/hardware-keyboard and device-resource tests remain gates. A previous app-auth timer expiry is not a five-minute continuous screen-lock test. See [physical evidence](research/physical-device-connection-debug.md).

## Deferred scope

No Mosh, backend, signup, companion, notifications, agent APIs/dashboard, files/editor/Git UI, SCP/SFTP browser, multiple simultaneous terminals, plugins, themes marketplace, iCloud sync or analytics SDK. Architecture changes require new acceptance evidence, not preference for novelty.
