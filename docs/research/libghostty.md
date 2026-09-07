# libghostty investigation

Observed 2026-09-06 locally; some GitHub timestamps are already 2026-09-07 UTC. Repository snapshots and package versions matter more than search-result dates.

## Finding

A complete iOS remote frontend is feasible through community work, but **unmodified upstream full libghostty is not an officially supported iOS frontend**. Upstream `src/build/Config.zig` explicitly rejects full iOS builds and directs consumers to `-Demit-lib-vt`. The `include/ghostty/vt.h` API warns that it remains incomplete and unstable. This falsifies the simple assumption that Ghostty's macOS embedding library can be dropped into an iOS app unchanged.

Evidence: [upstream configuration at 82938b633ba6](https://github.com/ghostty-org/ghostty/blob/82938b633ba646db38591d969c3c526332bd7e65/src/build/Config.zig), [VT header](https://github.com/ghostty-org/ghostty/blob/82938b633ba646db38591d969c3c526332bd7e65/include/ghostty/vt.h), [build definition](https://github.com/ghostty-org/ghostty/blob/82938b633ba646db38591d969c3c526332bd7e65/build.zig). Upstream's [1.3 release notes](https://ghostty.org/docs/install/release-notes/1-3-0) describe a separate libghostty release direction; application versions do not establish a stable embedding ABI.

## The layers are different

| Layer | What it supplies | Consequence for MoshDeck |
| --- | --- | --- |
| Ghostty application | Desktop UI, configuration, process/PTY management | Do not port the macOS app |
| Full libghostty embedding API | Surface, renderer, fonts, input, app callbacks and normally local process I/O | Community patches needed for iOS and host-managed I/O |
| libghostty-vt | Parser, terminal state, grid, scrollback/reflow, input encoding, render-state access | Appropriate core for remote bytes; not a UIKit view or a complete Metal renderer |
| Platform frontend | Metal/CoreText, display scheduling, keyboard/IME, selection, accessibility, clipboard | Large responsibility unless reusing a maintained wrapper |
| Transport | SSH PTY bytes and resize | Belongs to the host app, not Ghostty or a local iPhone PTY |

The VT API includes state/formatting/snapshot facilities and optional features; those do not turn it into the full desktop surface. Upstream builds a VT XCFramework. Writing a new renderer on top of VT would be substantial implementation and is rejected for this MVP.

## Concrete candidate

Evaluate [Lakr233/libghostty-spm](https://github.com/Lakr233/libghostty-spm/tree/733ae3b29d447b6707cbfc00879027a076dfd0eb), package release `1.5.20260906`, first. Its `GhosttyTerminal` product supplies `UITerminalView`, `TerminalSurfaceView`, SwiftUI state, CoreText/Metal rendering, input, selection, and `InMemoryTerminalSession`. This is a community package, not an upstream-supported Ghostty iOS SDK.

The inspected manifest points to upstream core `c4e16970a803b170e352432424f44192cb59f3ac`, patched in the package's `Patches/ghostty`. The XCFramework release `upstream.c4e16970a803` has SHA-256 `bd9bba3b95652900e87a6a0f190f33d82a1d8e42d1c0119c330072be361385da`. GitHub reports a **77,133,914-byte compressed multi-platform archive**. This is download size, not installed iPhone application size. The first frontend-only build measured a 19,498,214-byte device slice (all files) and a 9,505,864-byte unsigned release executable; see [results](spike-results.md). Full-app archive/install size and App Store thinning remain unmeasured.

Use exact package versions and commit `Package.resolved`; the wrapper's recommended `from:` range intentionally tracks frequent upstream-main builds and is inappropriate for an uncontrolled production update. Historical 1.4 tags were withdrawn according to its current README. Preserve artifact provenance/checksums and a reproducible rebuild path before distribution.

### Stream adapter

- Create the surface and host-managed session before enabling network reads; the wrapper buffers only up to a cap before attachment and can drop oldest pre-surface output.
- SSH stdout bytes go unchanged to `InMemoryTerminalSession.receive(Data)`. Do not decode each chunk as UTF-8: sequences and multibyte characters cross reads.
- The session's `write` callback receives encoded user input **and terminal replies**. Deliver both to the current SSH channel in order.
- The `resize` callback supplies grid and pixel sizes. Request initial PTY dimensions before exec and send SSH window changes afterward.
- Use `.paste(text:)` for composer text and `.sendKey` for control keys. Newline is not an Enter key event.
- Serialize transport writes, preserve partial writes/backpressure, and reject callbacks from an old connection generation. Keep parsing off the main thread and view state on the main actor.
- On reconnect create a fresh terminal surface and let tmux redraw. Never concatenate a new tmux redraw onto a stale parser state or replay arbitrary saved escape streams into a live channel.

See [session implementation](https://github.com/Lakr233/libghostty-spm/blob/733ae3b29d447b6707cbfc00879027a076dfd0eb/Sources/GhosttyTerminal/InMemory/InMemoryTerminalSession.swift), [manifest](https://github.com/Lakr233/libghostty-spm/blob/733ae3b29d447b6707cbfc00879027a076dfd0eb/Package.swift), and [patch inventory](https://github.com/Lakr233/libghostty-spm/blob/733ae3b29d447b6707cbfc00879027a076dfd0eb/Patches/ghostty/README.md).

### What the fork costs

The patch stack adds host-managed I/O, Darwin library packaging, iOS build support, IOSurface alignment/presentation fixes, simulator kqueue handling, and removal of a private window-blur API. It also removes shaders, inspector, Sentry, and desktop runtime dependencies. Patch variants adapt to upstream internal changes. This is evidence of maintenance work already needed, not evidence that every current device bug is fixed.

The package can be consumed without maintaining a MoshDeck fork initially, but a **patched upstream dependency remains necessary** for this choice. Budget recurring upgrade qualification across Xcode, Zig, core, wrapper, and iOS. A narrow adapter limits API exposure; it does not eliminate ABI, renderer, or supply-chain risk.

The wrapper's default local-file paste/drop behavior can insert iOS container paths, which are meaningless to the remote Mac. Disable file/image staging and file drops for the spike; allow explicit plain-text paste only. Audit OSC 52 and newer clipboard protocols at the callback boundary. Disable `TerminalDebugLog`, whose input/output categories can include payload excerpts. Do not enable clipboard read merely to match a desktop default.

## Existing examples and alternatives

- Package `Example/MobileGhosttyApp`: UIKit keyboard, safe area, selection and host-managed backend; useful implementation reference, not proof of SSH or device lifecycle behavior.
- [Remux](https://github.com/h3nock/remux/tree/d098ec6ae5165116e32621b265ec934b087fb5c0): MIT iOS app with its own Ghostty build and Citadel fork, tmux control mode and native pane projections. Strong evidence for feasibility; its deeper tmux coupling is not appropriate for our raw-shell MVP.
- [expo-libghostty](https://github.com/arcboxlabs/expo-libghostty): another consumer of community Apple packaging. Does not justify adding React Native/Expo.
- [iGhostty](https://github.com/OwnGoalStudio/iGhostty): jailbreak-oriented local-shell environment. Not an App Store execution model to copy.
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm): MIT, existing UIKit remote-terminal examples and production consumers; the fallback if the Ghostty spike fails. Its current main documents a 2.0 API transition; pin a tested release, not main.
- xterm.js/WKWebView: mature terminal engine, but extra JavaScript bridge and WebView keyboard/rendering concerns. No evidence it beats a working native frontend for this user's priorities.

## Correctness acceptance

Test both direct SSH shell and tmux with VT/xterm cursor addressing, erase/scroll regions, 256/true color, alternate screen, scrollback/reflow, bracketed paste, OSC titles/hyperlinks, cursor shapes, mouse reports, UTF-8 chunk boundaries, CJK/double-width, combining accents, emoji/ZWJ and selection. Exercise vim, neovim, less, htop, Codex and Claude Code. Record TERM outside and inside tmux. No renderer claim bypasses this matrix.

Start the outer PTY as `xterm-256color`; tmux normally advertises `tmux-256color` internally where terminfo exists. Enable true-color terminal features only when verified. Do not advertise `xterm-ghostty` to a host without its terminfo. Both tmux and Mosh add terminal interpretation layers that can constrain end-to-end features.

Decision: **community full Ghostty frontend for the bounded spike, medium confidence**. No custom renderer; no claim of upstream iOS support. Adopt for daily use only after real-device correctness, privacy, performance, and rebuild checks pass.
