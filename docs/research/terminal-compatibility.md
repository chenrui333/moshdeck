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
