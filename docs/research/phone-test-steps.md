# Physical phone test steps

Run one test at a time on the installed build. These are instructions, not passed results. Record results in [physical-device evidence](physical-device-connection-debug.md). The app should attach to an existing disposable tmux session; do not start these tests in a production shell or interrupt a valuable agent task.

For TestFlight build 4, direct hardware checks were waived for this iteration; these steps are available for voluntary beta feedback. Record the actual installed version/build. Simulator or earlier-build results do not establish acceptance of this build. Native session switching checks are in section 7 below.

Before each test, connect and run:

```sh
echo ready
echo $$
```

Note the shell PID. After recovery, repeat `echo $$` in the same pane. A matching PID plus the unchanged tmux pane identifies shell continuity. For later agent acceptance, separately verify the agent process; a surviving shell alone does not prove agent survival.

## 1. Complete outage

1. While connected, enable Airplane Mode and ensure Wi-Fi is also off.
2. Return to MoshDeck and stay offline for one minute.
3. Once the app displays Reconnecting/disconnected, raw input and sending must be disabled. The composer draft can remain editable. Do not use a destructive command to test this.
4. Restore connectivity and return to MoshDeck. Wait 30 seconds without tapping Connect.
5. If recovered, run `echo recovered` and `echo $$`. Otherwise record the visible state/error, then try Connect once.

Record whether recovery was automatic or manual, Face ID occurred, the PID matched, and the approximate time from network restoration to usable input. Thirty seconds is an observation checkpoint, not proof retries are exhausted. Turning off Wi-Fi alone is a roaming test, not a full outage. Opening Control Center may cause scene inactivity; record this as part of the actual test.

## 2. Foreground unlock

1. Authenticate, connect, and keep MoshDeck foregrounded for six continuous minutes.
2. Occasionally type a harmless command to prevent phone auto-lock.
3. After six minutes, run `echo still-here`.

Expected: no app authentication timeout or app-lock disconnection. If the phone locks or another app opens, record the interruption and repeat; this cannot prove uninterrupted foreground use. Record network interruptions separately.

## 3. Screen lock

1. Connect and note the shell PID.
2. Lock the phone for six minutes, measuring actual absence.
3. Unlock the phone, open MoshDeck and authenticate when required.
4. Observe automatic recovery, then run `echo $$`.

Repeat as separate tests for 20 and 60 minutes. Expected: app authentication after five minutes away, then recovery to the existing session if it survived on the Mac. A six-minute foreground test does not substitute for screen lock. Also test a 30-second background interval separately; it should avoid new app authentication.

## 4. Network transitions and process termination

- Wi-Fi to cellular: begin on Wi-Fi, disable Wi-Fi with cellular enabled, return to the app, and verify input/PID. Record the actual network settings.
- Cellular to Wi-Fi: begin on cellular, enable/connect Wi-Fi, return, and repeat the same checks.
- App termination: connect and save a synthetic composer draft by dismissing it, remove MoshDeck from the app switcher, reopen, authenticate, and connect if needed. Verify PID/profile/draft. Local terminal pixels are not expected to survive process termination.

Do not infer one direction or termination behavior from a different test.

## 5. Composer and copy

1. Open Compose, enter two harmless lines, dismiss it and reopen. Confirm retention.
2. Background/resume and repeat. Verify app-switcher concealment without recording private text.
3. Long-press terminal text, select text in the native sheet and Copy; paste into a local note to verify it. Use synthetic ASCII, Chinese, emoji and combining text.
4. Use Clear draft and confirm; reopen the composer and later relaunch to verify the saved value is empty.
5. Test 1 KB, 10 KB and 50 KB synthetic prompts with a suitable disposable foreground program. Inspect the paste confirmation. Paste adds no separate Enter, but embedded newlines may execute in a shell without bracketed-paste protection. Never test arbitrary multiline paste in a valuable shell.

Copy, composer input, application interpretation of bracketed paste and SSH byte preservation are different checks. Local integration tests do not fill these physical rows.

## Result format

```text
Build:
Test:
Actual duration / network change:
Automatic or manual reconnect:
Face ID:
Time to usable:
Same shell PID:
Draft retained:
Old screen retained:
Visible error:
```

Send structural results, not terminal transcripts or credentials. The engineer can correlate sanitized attempt timelines and Mac tmux metadata. Broader real-app and agent tests remain in [terminal compatibility](terminal-compatibility.md).

## 6. Disposable CLI and coding-agent acceptance

After completing the current session's timed recovery tests, prepare a separate workspace on the Mac:

```sh
python3 Spike/scripts/prepare-terminal-acceptance.py
```

The helper creates a new temporary Git repository, makes a DCO-signed baseline commit, and runs three standard-library Python tests. It prints the workspace path. It does not start an agent, connect remotely, or alter existing tmux sessions. Assign the printed path to `WORKSPACE`, then explicitly create a separate session when ready:

```sh
tmux new-session -s moshdeck-acceptance -c "$WORKSPACE"
```

Do not replace the original recovery-test session. In MoshDeck, connect an attach-only profile to `moshdeck-acceptance`. Begin with `echo $$`, `cat sample.txt`, `less sample.txt`, `vim sample.txt`, `git log`, and `python3 -m unittest -v`. Check scrolling, resize, Esc, arrows, Tab and clean exit separately; merely running the commands is not a visual PASS. Avoid live cluster/cloud commands when checking kubectl/Terraform; client help/version output can establish basic rendering only.

For the agent workload, start Codex in this workspace and ask it to carry out `TASK.md`. Use the phone for a normal prompt, a longer composer prompt and streaming-output inspection. Exercise Ctrl-C during active work and then deliberately resume. Record the agent PID separately from the shell PID, background/recover, and verify that same process before returning to an actual iTerm2 attachment. Repeat the inverse handoff in a separate observation. Agent APIs are not involved, and no private prompts/output should be recorded.

This setup is preparation, not physical acceptance. Record missing tools/hardware and untested interactions explicitly. A passing Python baseline does not pass any phone terminal or agent row.

## 7. Native session switching and shared Mac control (build 4)

Use two existing disposable tmux sessions. If a second session is needed, explicitly create one from a Mac shell with a unique name, for example `tmux new-session -d -s moshdeck-beta-peer`; do not replace an existing session. List them with `tmux list-sessions`. In iTerm2, attach the first with `tmux attach-session -t SESSION_NAME`.

1. Attach the phone to that same session/pane. At a shell prompt, run `echo PHONE` on the phone and `echo MAC` on the Mac. Both screens should reflect both commands. Record the shell PID and pane before switching.
2. Tap **Sessions** and choose the second session. The phone must change; iTerm2 must stay on the first session. Inspect **Reconnect target** in the panel or terminal actions menu: it changes only after a confirmed native switch.
3. Return through the picker. Swipe left toward the next session in the displayed alphabetical order, then right to return. Confirm the destination preview, real remote switch and original shell PID. There is no wraparound; use the picker if additional sessions lie between the two test sessions.
4. Release a short drag before the threshold; no switch should occur. Scroll vertically, select/copy synthetic terminal text, and move horizontally during selection. None should change sessions.
5. Disconnect/reconnect after a successful native switch. The phone should attach to its newly saved target. Contrast this with **Open terminal picker (Ctrl-B, s)**: manual tmux switching does not update the saved target.
6. During the separate outage test, confirm swiping and sending are unavailable while reconnecting. Recovery must not replay a gesture or keystrokes.
7. With both clients on the same session again, disconnect the phone and confirm Mac input still works. Reattach the phone, then detach only iTerm2 with Ctrl-B followed by D; phone input should still work. Reattach both and compare the original pane/shell PID. Do not use `exit`, which ends a shell.
8. Repeat switching away/back during a disposable coding-agent task. Record survival of the actual agent PID separately; the shell test alone does not prove agent continuity. Enter prompts rather than shell commands while the agent owns input.

If a target disappears or a switch fails, record the error and whether the original attachment remains usable. Do not terminate valuable sessions to manufacture this case. A failed switch must not create a replacement or change the saved target. Report each item separately as PASS, PARTIAL, FAIL or NOT TESTED; include only structural results and sanitized diagnostics, never private output.
