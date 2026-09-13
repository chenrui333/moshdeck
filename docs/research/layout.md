# iPhone terminal layout investigation

Reviewed September 12, 2026 against current product documentation, vendor screenshots and the checked-out app/wrapper source. Recommendation for the next UI iteration, not a claim of implemented or physically validated behavior. The accepted SSH/Ghostty/tmux architecture and one-active-terminal MVP remain unchanged.

## Recommendation

Use a terminal-first phone layout: one compact host/status header, a dedicated tmux action menu, a one-tap composer, an edge-to-edge terminal, and one keyboard accessory row. Borrow iTerm2's clear context and emphasis on terminal content; adapt actions to touch and the small viewport. Remove the Fixture/SSH tab bar from release navigation. The synthetic fixture remains in Debug builds and UI tests.

The owner repeatedly needed explanations for which session was shared, how to attach from Mac, and how to switch from the phone. Keyboard dismissal previously obscured navigation. These observed problems justify the change; visual resemblance to a desktop application alone does not.

## Evidence and useful patterns

| Reference | Observed pattern | Decision for MoshDeck |
| --- | --- | --- |
| [iTerm2 status bar](https://iterm2.com/documentation-status-bar.html) | Context information, composer/actions, and priority-based layout when space runs out | Keep host and transport state legible; keep primary controls in stable positions. Do not add desktop tabs, split-pane controls, resource graphs or shell-integration dependencies. |
| [Blink quick start](https://docs.blink.sh/) | Terminal-first interaction, Smart Keys above the software keyboard, optional/contextual controls and gestures | Keep a compact key row. Provide visible entry points for important actions: the owner has already found hidden keyboard sequences difficult to discover. |
| [Prompt 3.5](https://www.panic.com/prompt/) | Vendor iPhone screenshot devotes nearly the entire available area to terminal content, with a single special-key row; configurable keyboard advertised | Reclaim terminal space and preserve readable controls. Screenshot density is not evidence that its small font is appropriate for our user's eyes. |
| [Termius touch terminal](https://termius.com/blog/new-touch-terminal-on-ios) | Touch cursor/arrow gestures and an extended keyboard for less frequent keys | Keep direct arrow buttons first; gestures may supplement them after physical testing. Do not make a new gesture the only path to Escape, switching or dismissal. |
| [Termius navigation](https://termius.com/blog/termius-for-ios-new-navigation-and-sftp) | Distinct iPhone bottom-navigation and desktop-like iPad layouts | Mobile and desktop layouts should differ. Its Vault/Connections/Profile destinations solve a broader product than our one-terminal MVP and do not justify an equivalent bottom tab bar here. |
| [ShellFish agentic coding](https://secureshellfish.app/help/agentic-coding) and vendor screenshot | Compact host toolbar, terminal content, special keys and keyboard dismissal; documented dictation shortcut | Explicit, reachable keyboard dismissal and native prompt composition fit the workflow. Location persistence, notifications and shell integration are not adopted. |
| [Apple: Keep up with the keyboard](https://developer.apple.com/videos/play/wwdc2023/10281/) | SwiftUI keyboard safe areas and UIKit keyboard layout guides account for changing keyboard geometry | Use supported layout ownership instead of subtracting a fixed keyboard height. Preserve the current working renderer/resize boundary. |

This is a documentation/screenshot comparison, not hands-on benchmarking of these apps. Blink's contextual-bar image, Prompt's iPhone image and ShellFish's agentic-coding image were visually inspected; none was copied into the app or repository. Older vendor articles describe documented design decisions, not proof that every current app screen is unchanged. Apple's HIG toolbar/keyboard pages required JavaScript in the text fetcher; the accessible WWDC transcript supplied the keyboard-layout evidence.

## Current app findings

- `Spike/App/MoshDeckSpikeApp.swift` includes both Fixture and SSH tabs even in Release. Release selects SSH initially, but does not remove Fixture.
- The top safe-area row contains Expand/Restore and Hide Keyboard. The remote screen then stacks status, diagnostics, Lock, help and other connection controls vertically.
- A separate SwiftUI row supplies Esc, Ctrl-C, Ctrl-B and Compose. The pinned Ghostty wrapper also supplies a keyboard accessory. This duplicates terminal controls and consumes height at the moment the software keyboard already reduces the viewport.
- The pinned wrapper supports ordered `inputAccessoryItems`, an empty list to hide its bar, and public modifier/input APIs. A wholesale renderer or key-encoder replacement is unnecessary.
- Its built-in accessory is 52 points high, with 36-point button sizing and horizontal scrolling. A customized native strip must verify hit targets and accessibility; do not assume existing drawing dimensions prove comfortable touch targets.
- `RemoteTerminalModel` already owns its lifecycle, transport, terminal, draft and saved target; `SSHConnection` is an instance actor. The remaining singleton profile storage is an eventual migration concern, not a reason for a multi-session refactor now.

## Proposed connected layout

Conceptual wireframe; widths and heights require device validation:

```text
┌──────────────────────────────────────────┐
│ MacBook • Connected   tmux   Compose   ⋯ │
├──────────────────────────────────────────┤
│                                          │
│              Live terminal               │
│                                          │
│       tmux's own session/status line      │
├──────────────────────────────────────────┤
│ Esc  Ctrl  Tab   ↑  ↓  ←  →   Hide keys   │
├──────────────────────────────────────────┤
│              iOS keyboard                │
└──────────────────────────────────────────┘
```

Header: a compact adaptive row, with the configured host on the leading side, text-supported connection state, a labelled `tmux` menu, composer action and overflow menu. Compose may use the familiar compose symbol with an explicit accessibility label. Host text truncates before action targets shrink. The displayed host is the SSH endpoint, not a claim about a nested SSH destination. A tap on the host opens connection details, including the complete address and **saved reconnect target**.

The app cannot currently observe arbitrary tmux session switches or the foreground agent. Do not label a saved `work` profile as the verified live session, show a fabricated client count, or advertise “Mac also connected” without observation. The actual tmux status line remains authoritative for the live session. The help panel explains how to prove shared control with visible markers.

The terminal gets all remaining safe area. No rounded terminal card, decorative padding, host form, diagnostics stack, always-visible Disconnect or Fixture/SSH tabs. Keep a solid high-contrast background behind text. JetBrains Mono remains the terminal font; native controls/composer keep iOS text behavior and Dynamic Type.

With the software keyboard visible, show one accessory row. Eight 44-point interaction targets can fit within a typical 390-point phone width with modest insets; this is a sizing hypothesis, not a measured acceptance result. On narrower widths, keep Escape and dismissal fixed and allow the key region to scroll with a visible overflow cue. Never compress targets solely to fit every key. Alt, extra control combinations and navigation keys can live in a secondary key palette. Ctrl must visibly distinguish armed and locked states and reset on existing focus/lock/disconnect paths.

With the keyboard hidden, reclaim the key row and retain a clear Show Keyboard affordance. A hardware keyboard should not force a redundant full software key row. Keep any compact system input assistant behavior accounted for. Normal use is already spacious; Expand/Restore is no longer a necessary primary control. A later focus mode must not be needed to find the terminal or escape the keyboard.

## Actions and state behavior

| Area/state | Behavior |
| --- | --- |
| `tmux` menu | Switch sessions (label the default Ctrl-B s sequence), Send Ctrl-B, Attach from Mac/help. One SSH connection, no native list model or control-mode protocol. |
| Switch action | A deliberate terminal key sequence, using existing input encoding and attempt/input gating. No pasted shell command that could land inside an agent prompt. No deferred/offline replay. Custom tmux prefixes remain manual; do not rewrite the user's config. |
| Composer | Native editing sheet with explicit Paste and separate Enter, retained draft and Done. Sending disabled while offline; editing remains available while the app is unlocked. The terminal owns raw Return semantics when the composer is closed. |
| Overflow | Connection details/settings, diagnostics, help, Disconnect and Lock. Separate Lock from Disconnect. A compact menu is appropriate for infrequent actions, but not the only way to hide the keyboard. |
| Locked | Existing privacy cover and explicit Unlock. Do not display host/session/draft beneath an unlocked-looking navigation shell. |
| Disconnected first launch | A concise saved-host/setup screen with Connect. Full profile editing belongs in its own form. Keep first-time key/host verification explicit. |
| Connecting | Progress and Cancel from the actual state machine. No repeated authentication in connect/retry. |
| Reconnecting | Retain last screen and draft; show a clear status overlay. Disable all raw input and sending. Host/session help stays reachable while app access is permitted. |
| Failed | Actionable short reason, Retry and Details. Preserve the first error; do not show a generic silent return to Connect. |
| Detach/end | Explicit Disconnect clears desired connection intent. No UI close control sends `exit`, Ctrl-D or kills a tmux session. |

The tmux menu improves discovery of existing mechanisms; it is not a native session picker. In the current ownership model, reconnect still returns to the saved target after a live tmux switch. Explain this in the menu/help until a separately justified session-awareness mechanism exists.

## Fixture decision

Keep the fixture for terminal regressions: parser behavior, alternate screen, Unicode, paste/input and keyboard tests. Remove it from the shipped app's normal navigation with a Debug/test-only route, preserving the selectors and coverage used by automation. Do not delete the fixture or repurpose its synthetic output as a fake connected terminal. Verify the Release UI has no fixture destination and the Debug tests still execute their intended selectors.

## Incremental implementation and acceptance

1. Remove Release fixture navigation and move infrequent controls into a stable header/menu. Keep the renderer instance, `.id` ownership and connection code unchanged. Verify Release startup and Debug fixture tests.
2. Add the labelled tmux menu and keep Mac attachment help adjacent to it. Test the actual phone Ctrl-B path and switching between two existing sessions, then document reconnect's saved-target behavior.
3. Consolidate keyboard controls using the wrapper's existing input/modifier APIs. Test all primary keys, focus transitions, selection, CJK composer input and no duplicated/offline input.
4. Exercise keyboard show/hide and composer open/close in portrait/landscape on the real phone. Ensure no obscured controls, lost draft, terminal reset or repeated resize/render failure. Check larger accessibility text outside the terminal and VoiceOver labels.
5. Repeat shared iTerm2/phone agent control and interruption tests against the resulting build. Layout work does not waive the required 20/60-minute locks, full outage, both network directions, termination or meaningful agent dogfood.

Compare old and new terminal row counts on the same physical phone, font and keyboard state. Accept the change only if it increases useful terminal space while the user can find Mac attachment, switching, composer and keyboard dismissal without verbal coaching. Measure action count and observed errors rather than claiming the mockup is the “best” layout before use.

No native tabs, split panes, file browser, agent dashboard, theme system, Mosh, companion or backend is introduced by this recommendation.

## Implementation checkpoint — September 12, 2026

**LAYOUT IMPLEMENTED — PHYSICAL VALIDATION PENDING.** Implementation commits: `59903a9` (Release fixture exclusion), `1216a37` (keyboard consolidation), `c90efdd` (compact context, menus and presentation). The initial research above remains rationale; it is not physical acceptance evidence.

Implemented:

- Release opens the app-lock/SSH surface directly. Fixture code and the Fixture/SSH tab bar compile only in Debug. Authentication/echo diagnostic profile choices are also Debug-only; ordinary shell startup choices remain available in Release.
- One host/status header replaces the stacked status/help/diagnostics/lock controls. Connected status is compact. Host truncation is visual only; full host, username, port and **Reconnect target** appear in Connection Details.
- Compose remains a direct, VoiceOver-labelled action. Its native editor, Keychain draft path, explicit paste confirmation and separate Enter action remain. Draft editing is available while unlocked and disconnected; sending still uses the existing live-state guards.
- The tmux menu sends Ctrl-B followed by lowercase s through Ghostty's key API, exposes Ctrl-B alone, labels the saved reconnect target honestly and links Mac attachment help. Actions are synchronous, deliberate and live-gated. No session query, control-mode client, shell-command paste or delayed input was added. Custom prefixes remain manual.
- Overflow contains Connection Details, Profile / Settings, Copy Diagnostics, Disconnect and Lock app. Profile editing requires stopping the active connection first. Disconnect and Lock retain their separate existing methods and intent semantics.
- A single UIKit input accessory replaces the wrapper's visible default accessory and the separate permanent Esc/Ctrl-C/Ctrl-B row. It contains Escape, sticky Ctrl, Tab, four arrows and Hide Keyboard. Buttons have at least 44-point interaction targets; Escape and dismissal stay at the edges, and the middle region can scroll horizontally on narrow displays. The accessory is 48 points high.
- Sticky Ctrl uses the existing Ghostty state machine and public change callback. Armed/locked state is visible and exposed as an accessibility value. Existing focus-loss reset remains. Key buttons consult the existing live state before dispatch; the transport/input pipe is unchanged.
- A Show Keyboard header action appears when terminal focus is dismissed. The normal expansion control is removed. Tapping the live terminal also uses its existing focus behavior.
- Reconnect retains the same displayed surface until the existing lifecycle promotes a replacement. Progress/Cancel or failure/Retry/Details appear compactly above it. The existing `.id(ObjectIdentifier(terminal))`, byte stream, resize callbacks, authentication policy, retry rules and attach-only recovery remain intact.

### Local verification

| Check | Result | Scope |
| --- | --- | --- |
| Release startup, no fixture navigation, locked profile | PASS: 1 named simulator UI test, zero failures | Executed in Release, not a skipped Debug selector; repeated after header implementation |
| Debug fixture parser/input, app-lock setup, composer background retention, accessory interaction | PASS: 4 named simulator UI tests, zero failures | Includes a 30-second synthetic composer background test |
| Accessory bytes | PASS within the UI test | Actual button taps and Ctrl+c produced the expected control/escape/Tab/arrow bytes in the synthetic session; no remote transcript captured |
| Ctrl and focus | PASS within the UI test | One-shot activation clears after c; armed state clears after dismissal and reopening |
| Keyboard/rotation | PASS within the UI test | Three repeated hide/show cycles and landscape hide/show; button hit bounds checked at 44 points minimum |
| Lifecycle, app-lock, input pipe | PASS: 21 selected tests in 3 suites | Includes stopped-attempt/offline replay and first-failure/attempt ownership coverage; no core implementation changes |
| tmux command/generation rules | PASS: 4 tests, including 7 invalid-name cases | Attach-only recovery, command quoting and generation-bound paste/reconnect |
| Changed Swift files | Strict swift-format lint and `git diff --check` PASS | Composer sheet content made an explicit closure argument to resolve the previous formatter warning, without changing dismissal persistence |
| Signed physical-device Release build | BUILD SUCCEEDED; strict signature verification passed | Installed version 0.0.1 (2), source `c90efdd`, on the paired iPhone 15 Pro Max |
| Physical launch | NOT TESTED | Automated launch was refused by iOS because the phone was locked; installation success does not prove runtime acceptance |

The first Release simulator invocation requested Intel slices that the source-built Ghostty artifact does not contain and failed at link. The supported arm64 simulator invocation with `ONLY_ACTIVE_ARCH=YES` passed. This is a build-command correction, not an architecture or dependency change.

### Physical acceptance and viewport record

The previous installed phone build was 0.0.1 (1). A baseline estimate was requested before replacement, but no before/after row counts have been reported at this checkpoint. Do not infer phone height from a simulator, a tmux client size with unknown keyboard state, or the wireframe.

| Phone state, composer closed | Before | After |
| --- | --- | --- |
| Keyboard hidden | NOT MEASURED | NOT MEASURED |
| Keyboard visible | NOT MEASURED | NOT MEASURED |

Source-level improvement: Release removes the tab bar, global expansion/dismissal bar, permanent diagnostics/lock/help stack and duplicate terminal action row. The 48-point accessory replaces the wrapper's 52-point row. The terminal-space benefit still needs measurement on the actual phone at the same font size, orientation and keyboard state.

| Physical iPhone 15 Pro Max workload | Result | Remaining observation |
| --- | --- | --- |
| Shell | NOT TESTED | Commands, readable output, scrollback, viewport height |
| Codex | NOT TESTED | Streaming, long composer prompt, Ctrl-C and readability |
| tmux/shared Mac | NOT TESTED | Menu switch, two sessions, both-client input and detach survival |
| Keyboard | NOT TESTED | Repeated hide/show, clipping, focus, portrait/landscape PTY resize |
| Composer | NOT TESTED | Draft retention, native/CJK editing, paste and separate Enter |
| Reconnect | NOT TESTED | Screen retention, visible state, disabled sending, successful recovery |

No connection/input regression appeared in the executed local checks. Physical regression status is unverified. VoiceOver reading order, larger Dynamic Type with the full connected header, hardware-keyboard presentation and narrow-width accessory scrolling still require use on a device. No further visual redesign is justified until those observations arrive.

The earlier exported build-2 archive predates these changes and must not be uploaded as this layout beta. A new distribution archive/export is required after the chosen acceptance checkpoint; the installed development-signed Release app is not a TestFlight upload.
