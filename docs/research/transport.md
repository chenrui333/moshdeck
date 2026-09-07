# Transport investigation

Observed 2026-09-06. Recommendation: **ordinary SSH over the existing official Tailscale VPN, backed by tmux**. Mosh is a later experiment triggered by measured user pain, not by the working name.

## Three independent kinds of persistence

1. tmux keeps remote PTYs and processes alive when clients detach. It does not survive reboot or a killed tmux server.
2. SSH/TCP or Mosh determines transport continuity, failure detection and screen recovery.
3. iOS decides whether MoshDeck executes at all. Neither transport grants background runtime.

Tailscale can preserve the inner endpoint addresses while the phone's physical network changes. An SSH TCP connection may therefore survive a brief handover. This is a hypothesis to test, not a promise: tunnel interruption, timeouts, VPN state, server policies and iOS suspension still break it.

## Deployment alternatives

| Option | Benefits | Costs / reason not selected |
| --- | --- | --- |
| A. Tailscale + macOS OpenSSH | Private addressing, ordinary SSH authentication, mature Mac service; no router SSH forwarding | Selected; requires Tailscale and Mac reachability |
| B. Tailscale + Tailscale SSH | Tailnet identity-based auth, centralized SSH policy and optional check mode | macOS server support is distribution-specific; adds auth/control-plane coupling and browser check UX |
| C. Tailscale + Mosh | Local prediction, screen-state resynchronization, UDP roaming | Extra client/server and terminal interpretation layer, license work, UDP grants; benchmark only if A fails usability gates |
| D. Public Internet + Mosh | Roaming without VPN; interactive latency benefits | Public SSH bootstrap plus reachable UDP ports, NAT/CGNAT/firewall setup; avoid for personal Mac |
| E. Public Internet + SSH | Universal protocol | Public attack surface, NAT/dynamic-address management, network changes more likely break TCP |
| F. Custom relay | Could offer centralized reachability and notifications | New service, auth, availability and security ownership; no required MVP capability justifies it |

## Tailscale model and caveats

Install the official Tailscale app on both devices. MoshDeck uses normal DNS and TCP to a user-supplied MagicDNS FQDN or tailnet IP. No embedded Tailscale SDK, VPN extension, OAuth integration, tailnet API token, device enumeration or custom network protocol.

Tailscale provides private addresses, encrypted WireGuard paths, NAT traversal and access policy. It can relay encrypted traffic via DERP when a direct path is unavailable. **No MoshDeck backend does not mean no external infrastructure or no Tailscale account.** Coordination, identity-provider availability and sometimes relay performance remain dependencies. All paths are end-to-end encrypted; a direct peer path is preferred but not guaranteed. [Connection types](https://tailscale.com/docs/reference/connection-types), [control/data planes](https://tailscale.com/docs/concepts/control-data-planes).

MagicDNS simplifies naming; it is not an app-level discovery API. MVP users copy a hostname from Tailscale. Do not embed administrator credentials to produce a host picker. An active VPN may conflict with another VPN profile; the app should surface connection failure with a Tailscale setup hint, not automatically reconfigure VPNs. [MagicDNS](https://tailscale.com/docs/features/magicdns).

Use a narrow grant for this phone to this Mac's TCP 22. Avoid a user-wide source selector if the intent is one device: a user's identity can cover multiple machines. Validate policy with Tailscale's tests and current device identity. If evaluating Mosh, add a small explicit UDP range and configure the server accordingly. Tailnet policy does not protect macOS sshd from LAN/public interfaces it already listens on; inspect host firewall/listeners and router exposure separately.

### macOS variants and the SSH naming trap

| Mac installation | Ordinary macOS sshd over Tailscale | Tailscale SSH server | Operational point |
| --- | --- | --- | --- |
| Mac App Store app / Network Extension | Yes | Not supported by cited server docs | GUI/session-dependent; sandboxed |
| Standalone app / System Extension | Yes | Not supported by cited server docs | Tailscale's recommended general Mac distribution |
| CLI `tailscale` + `tailscaled` / utun | Yes | Supported | More administrator setup; unattended operation possible |

The Standalone CLI supporting the **client command** `tailscale ssh` is not evidence it hosts the Tailscale SSH **server**. Current official [SSH documentation](https://tailscale.com/docs/features/tailscale-ssh) and [macOS comparison](https://tailscale.com/docs/concepts/macos-variants) are the basis of this table; recheck if Tailscale changes support.

Tailscale SSH intercepts tailnet port 22 and uses its own SSH service/auth policy. Normal macOS OpenSSH instead uses Remote Login, the selected local account and its authorized keys. Choose the latter for independence and the existing Mac environment. Do not enable `tailscale set --ssh` casually: it changes which server receives those connections. Check mode is a later option only if using the supported deployment and accepting its browser reauthentication flow.

## Does Mosh add enough?

Mosh uses SSH to authenticate/start `mosh-server`, then encrypted UDP state synchronization. Its local prediction can make typing feel immediate at high RTT. It catches up to the latest screen instead of draining every obsolete byte, particularly valuable after loss or output floods. tmux cannot supply those latency benefits. [Protocol and FAQ](https://mosh.org/), [source](https://github.com/mobile-shell/mosh).

Mosh is not simply a reliable byte socket to swap into `SSHTransport`. It interprets terminal state on the server/client and synthesizes terminal output; its supported terminal features become another correctness limit. Traditional Mosh does not transfer the complete output history: use tmux copy mode for durable history. Features such as OSC behavior, extended keyboard protocols, true color and mouse handling must be checked against the chosen client/server versions. SSH's ordinary PTY stream better preserves the current terminal protocol negotiation. Mosh also does not provide SSH forwarding/SFTP as part of its interactive transport.

| Situation | SSH over Tailscale | Mosh over Tailscale | MVP conclusion |
| --- | --- | --- | --- |
| Wi-Fi to cellular, reverse | Inner IP stability can save TCP; otherwise reconnect/auth/attach | Can recover without new SSH bootstrap while client/server state survives | Measure both directions |
| 30 seconds in background | Socket might survive; execution not assured | State may survive, but client cannot run when suspended | Foreground recovery required either way |
| Lock/idle 5, 20, 60 minutes | Expect reconnect, fresh renderer, tmux redraw | Resume state may avoid login if retained; process death needs extra persistence or new bootstrap | tmux preserves the work; don't promise socket lifetime |
| Elevator/subway/airplane mode | TCP retransmission can delay detection; foreground deadlines bound reconnect | Resync and speculative echo improve apparent responsiveness | Strongest later Mosh candidate |
| High RTT / loss | Echo waits for remote response; head-of-line blocking | Prediction and latest-state sync can help | Measure input-to-echo and recovery |
| Large output | Must handle ordered stream with bounded queues/backpressure | Can skip obsolete screens | SSH must not freeze Ctrl-C or grow memory without bound |
| Resize | PTY window-change; tmux sends SIGWINCH | Size part of synchronized state | Application redraw still required |
| Server survival | tmux survives SSH client loss | mosh-server may also survive; tmux still recommended | Neither survives Mac power loss |

Proposed admission gate: compare on the same phone, network route and task, with at least ten handovers/resumes. Investigate Mosh if repeated usable-reconnect p95 exceeds five seconds after network recovery, if SSH loses control for more than ten seconds, or if high-RTT typing remains unacceptable. These are proposed product thresholds, not measurements. Compare Blink SSH and Mosh before writing Mosh code. DERP paths can reduce the benefit of UDP by carrying traffic through a reliable relay path.

## SSH implementation

Use **Apple SwiftNIO SSH 0.15.0** for the spike, with an explicit host-key validator and Ed25519 key auth. It directly supports SSH session/exec/shell, PTY allocation, window changes and the required modern algorithms. The controlled macOS server makes missing general-purpose compatibility tolerable. The choice is based on the required protocol subset, current maintenance, security hooks, and avoidance of a separately packaged C crypto stack—not merely native Swift.

Apple describes NIOSSH as protocol building blocks, not a complete production client. MoshDeck must implement connection/auth/channel deadlines, trust UI, key persistence, EOF/errors, request replies, bounded queues, cancellation and reconnect. Its transport adapter must not import the terminal UI. See [SSH comparison](ssh.md) and [dependency licensing](licenses.md).

Do not wrap NIOSSH in Citadel by default: the inspected Citadel manifest uses a third-party NIOSSH fork and adds key parsers/algorithms, increasing the dependency surface. If NIOSSH lacks a concrete required capability, compare libssh2 first. No automatic insecure algorithm fallback or trust-all verifier.

## Host setup prerequisite

Remote Login must allow the intended local user. Use a dedicated phone SSH key; credentials used by agents remain on the Mac. Keep agent forwarding off. Ensure the login shell can locate Homebrew tmux and tools; use a verified absolute tmux executable path in the host profile if necessary. Do not assume GUI terminal environment variables, unlocked Keychain access, or agent sockets automatically exist in a fresh SSH login. Attach to the existing tmux server as the same user and socket namespace.

Check Mac power/sleep, post-reboot FileVault/login availability, SSH access policy and Tailscale state before evaluating mobile reliability. These are deployment gates, not problems a new phone transport solves.
