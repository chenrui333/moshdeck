# MoshDeck

Raw remote control for your development terminal from iPhone.

Status: daily-use MVP implementation. The physical SSH/tmux feasibility spike works; the full reliability, terminal and real-agent acceptance matrix is still in progress.

The accepted architecture uses GhosttyTerminal, ordinary SSH over the official Tailscale VPN, and tmux for Mac/iPhone session continuity. Mosh is not an initial requirement. No custom backend or agent-specific protocol is planned.

- [Build the development app](Spike/README.md)
- [TestFlight beta status](docs/testflight.md)
- [Website and beta setup guide](site/README.md)
- [Daily-use MVP and prerequisites](docs/mvp.md)
- [Terminal compatibility](docs/research/terminal-compatibility.md)
- [Performance observations](docs/research/performance.md)
- [Product direction](docs/product-direction.md)
- [Architecture and decisions](docs/architecture.md)
- [libghostty investigation](docs/research/libghostty.md)
- [Transport comparison](docs/research/transport.md)
- [SSH libraries](docs/research/ssh.md)
- [Existing clients and agent features](docs/research/ecosystem.md)
- [Dependency licensing](docs/research/licenses.md)
- [iOS lifecycle](docs/research/ios-lifecycle.md)
- [Security threat model](docs/security.md)
- [First spike plan](docs/spike-plan.md)
- [Connection lifecycle](docs/research/connection-lifecycle.md)
- [Physical connection debugging](docs/research/physical-device-connection-debug.md)
- [UX debugging handoff](docs/research/ux-debug-handoff.md)
- [iPhone layout research and recommendation](docs/research/layout.md)
- [Actual results and open gates](docs/research/spike-results.md)

The [development app](Spike/README.md) has physical-iPhone SSH/tmux, command input and automatic recovery evidence. Longer lock/outage, broad terminal application and Codex dogfood tests remain acceptance gates; see the current matrices before relying on a specific capability.


## Share a running session between Mac and iPhone

Start persistent work inside tmux from the beginning. In iTerm2 on the Mac:

```sh
tmux new-session -A -s work
codex
```

In MoshDeck, enable **Use tmux**, set **Session** to `work`, and connect using the verified SSH profile. Both clients then address the same tmux pane and running process; input from either affects it. From another ordinary iTerm2 tab, use `tmux attach-session -t work`. Detach a client with Ctrl-B, then D; `exit` terminates a shell instead.

### Everyday tmux commands

Run these in an ordinary Mac terminal tab:

```sh
# See the available sessions.
tmux list-sessions

# Attach to the existing work session.
tmux attach-session -t work
```

Replace `work` with a name from the list. Configure MoshDeck to use that same name. If you are already inside tmux, switch sessions with **Ctrl-B**, release, then **S**, or run `tmux switch-client -t work` at a shell prompt rather than nesting an attachment. On iPhone, tap the **Ctrl-B** accessory button, type lowercase **s**, select a session with arrows, and press Enter. Detach with **Ctrl-B**, then **D**; leave the process running.

An existing process in an ordinary iTerm2 shell outside tmux cannot be adopted automatically. MoshDeck does not move local sessions or execute the coding assistant on the phone.

Multiple Mac tmux sessions and switching through Ctrl-B, then S are part of the MVP workflow. Native MoshDeck tabs and multiple concurrent SSH connections are post-MVP. Current recovery returns to the saved profile's session, even if tmux's picker switched the live client elsewhere. See [MVP scope](docs/mvp.md), [beta setup](site/public/setup/index.html) and [physical acceptance evidence](docs/research/physical-device-connection-debug.md).

### Native session switching

The build-4 candidate supports **swipe left → next session**, **swipe right → previous session**, and a visible **Sessions ▾** picker. A drag previews the destination; release past the threshold to switch, or shorten the drag to cancel. Picker and gestures use the same alphabetical order without wrapping. A confirmed switch changes only the phone's tmux client and saves its reconnect target, retaining the SSH connection and terminal renderer. Other Mac clients keep running. Direct physical checks for this iteration were waived in favor of beta feedback; see [TestFlight status](docs/testflight.md) for the distributed build.

Use `tmux new-session -d -s infra` at a shell prompt to create an additional session, then refresh the panel. Native selection is attach-only. The **Open terminal picker** fallback supports ordinary tmux navigation, but manual switches there do not update the saved reconnect target. One active phone terminal remains the supported model.
