# Physical phone test steps

Run one test at a time on the installed build. These are instructions, not passed results. Record results in [physical-device evidence](physical-device-connection-debug.md). The app should attach to an existing disposable tmux session; do not start these tests in a production shell or interrupt a valuable agent task.

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
