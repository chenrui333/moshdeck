# Terminal compatibility

Daily-use MVP matrix, September 7, 2026. PASS requires the actual physical app path. Availability, fixture parsing and Mac-only success do not establish interactive device compatibility. Capture structural notes only; never private terminal output.

| Workload | Result | Launch/render | Keyboard/scroll | Resize/alternate screen/colors/cursor | Exit/recovery |
| --- | --- | --- | --- | --- | --- |
| zsh shell | PARTIAL | Phone shell and commands passed in spike | Owner confirmed command use; scrolling not formally checked | Synthetic coverage only; shell geometry observed | tmux-backed recovery passed |
| bash | NOT TESTED | — | — | — | — |
| tmux | PARTIAL | Physical attach passed | Owner interaction confirmed | Phone/Mac PTY resizing passed; actual iTerm2 UI pending | Same pane/shell retained through recovery |
| less / man | NOT TESTED | — | — | — | — |
| vim | NOT TESTED | — | — | — | — |
| neovim | NOT TESTED | — | — | — | — |
| htop / top | NOT TESTED | — | — | — | — |
| git log / git diff | NOT TESTED | — | — | — | — |
| nested SSH | NOT TESTED | — | — | — | — |
| kubectl | NOT TESTED | — | — | — | — |
| terraform | NOT TESTED | — | — | — | — |
| Codex | NOT TESTED | Disposable repository required | Normal/long prompt, Ctrl-C, continue required | Streaming output and resize required | Same process across recovery and iTerm2 handoff required |
| Claude Code | NOT TESTED | Check installation first | — | — | — |
| CJK/Unicode | PARTIAL | Synthetic ASCII/Chinese, split UTF-8 fixture passed | Native composer and direct IME acceptance pending | Emoji/combining text present in fixture; width/copy visual acceptance pending | — |
| Hardware keyboard | NOT TESTED | Hardware availability unknown | Ctrl/Alt/Esc/arrows/Tab/deduplication pending | — | — |
| VoiceOver | NOT TESTED | Labelled controls exist | Actual navigation pending | Terminal accessibility pending | — |

## Input and stress checklist

- Composer: 1 KB, 10 KB and 50 KB; selection, dictation, paste versus explicit Enter, draft retention and no duplication.
- Draft: dismiss, failure, reconnect, background, relaunch and lock/unlock. Only the synthetic 30-second-background fixture has direct retention evidence so far.
- Output: burst, continuous moderate output, rapid updates, long history, Ctrl-C, resize and background while producing output. Exact 1 MiB transport test is Mac-only.
- Unicode: Chinese, optional Japanese, emoji, combining and double-width output; native-composer entry and pasted bytes; copy round-trip. Report direct terminal IME limitations separately.
- Keyboard: Esc, Ctrl, Tab, arrows, Ctrl-C and Ctrl-B first. Armed modifier clears on use/loss of focus/lock/disconnect; no hidden sticky state.
- iTerm2: real UI attachment, both directions of detach and active-client resizing. A generic local PTY passed the spike but cannot fill these rows.

Recommended synthetic fixture data should be public/disposable and not change live infrastructure. Codex acceptance must use a disposable repository; agent APIs are excluded. Exact version, build revision, operator, test steps and observed failure stage should accompany each completed row.

## Viewport copy implementation checkpoint

The pinned Ghostty UIKit wrapper requires `onTextSelectionRequest` for long-press selection. MoshDeck now handles that request with a read-only native text selection sheet and the wrapper-provided UTF-16 anchor. The snapshot covers the viewport, not all scrollback. It stays in memory, is discarded on dismissal, inactivity or explicit lock, and is concealed while inactive or locked. Remote OSC clipboard access remains denied. Physical long-press, selection, Copy, Unicode round-trip and privacy-cover acceptance are still NOT TESTED.

## Composer persistence checkpoint

Composer dismissal now saves the profile/draft through the existing device-only Keychain path, in addition to connection, lock and inactivity saves. Clear draft requires confirmation and saves the empty value immediately. The composer sheet explicitly conceals its contents on inactivity as well as app lock. Device validation of dismiss/relaunch, clear/relaunch and app-switcher concealment remains pending; abrupt process termination before a save is not guaranteed to preserve the latest edits.

## Large-input transport evidence

The isolated local OpenSSH integration test passed synthetic 1,024-, 10,240- and 51,200-byte UTF-8 payloads containing Chinese, Japanese, emoji, combining characters and newlines. It wrapped payloads in bracketed-paste delimiters, split writes every 31 bytes through TerminalInputPipe, and compared the server-side SHA-256 of the expected byte count before verifying shell input recovery. All three cases passed. This exercises queue/SSH/PTY byte preservation; it does not exercise Ghostty paste encoding, native composer behavior, mobile networks, or application interpretation of bracketed paste. Large-prompt physical composer acceptance remains NOT TESTED; basic composer use was subsequently owner-confirmed.

## Owner composer check — September 7, 01:14 EDT

The owner confirmed the composer check looked good on the installed recovery-fix build after screen-lock recovery. Record basic composer use as PASS (owner report). Do not infer separate passage of all size, clear/relaunch, clipboard, dictation, Unicode or process-termination cases from that short confirmation. Those detailed checks remain pending.

## Sticky modifiers after focus loss — 2026-09-07

The pinned UIKit wrapper's `resignFirstResponder` changes focus but does not reset its sticky Ctrl/Alt/Command state. A new synthetic check against the real platform view reproduced `FAIL: modifiers after focus loss` before the fix. The check arms Alt/Command and double-taps Ctrl, then resigns focus and checks for remaining active modifiers.

`PlainTextTerminalView` now invokes the wrapper's public `resetStickyModifiers()` before delegating focus resignation. Existing keyboard dismissal, scene inactivity, explicit Lock and transport cleanup all use this path. This preserves normal one-shot/locked modifier behavior while editing, but clears it when leaving the terminal input session. No upstream fork or alternate key encoder was introduced.

After the fix, simulator parser/input coverage passed in 7.406 seconds, and actual simulator keyboard dismissal/expansion passed in 13.487 seconds. Physical modifier-bar, hardware keyboard and reconnect acceptance remain pending; the phone build has not been replaced for this check.

## Disposable workspace preparation — 2026-09-07

`Spike/scripts/prepare-terminal-acceptance.py` was executed on the Mac and produced an isolated temporary Git repository with a DCO-signed baseline commit, Unicode/scrolling sample, coding task and three passing standard-library Python tests. No tmux session or coding agent was started; the existing phone continuity session was preserved. The [phone steps](phone-test-steps.md) describe the later explicit attachment and agent workflow.

A PATH availability check found tmux, vim, top, Git, OpenSSH, kubectl, Terraform, Codex and Claude. Neither nvim nor htop was on PATH. Availability is not terminal acceptance, and this check does not establish tool versions or account/authentication readiness. All corresponding unrun physical matrix rows remain unchanged.
