# MoshDeck

Raw remote control for your development terminal from iPhone.

Status: daily-use MVP implementation. The physical SSH/tmux feasibility spike works; the full reliability, terminal and real-agent acceptance matrix is still in progress.

The accepted architecture uses GhosttyTerminal, ordinary SSH over the official Tailscale VPN, and tmux for Mac/iPhone session continuity. Mosh is not an initial requirement. No custom backend or agent-specific protocol is planned.

- [Build the development app](Spike/README.md)
- [TestFlight preparation](docs/testflight.md)
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
- [Actual results and open gates](docs/research/spike-results.md)

The [development app](Spike/README.md) has physical-iPhone SSH/tmux, command input and automatic recovery evidence. Longer lock/outage, broad terminal application and Codex dogfood tests remain acceptance gates; see the current matrices before relying on a specific capability.
