# Physical-device connection investigation

Checkpoint 2026-09-06. Current result: **physical SSH shell connection reached connected with verified transport/PTY/output evidence**; owner-reported live command input/output now works; tmux and reconnect acceptance remain pending. The latest automated attempt stopped at app unlock, before SSH, because the unlock did not complete in its 45-second interaction window. This is not evidence that the earlier user-observed post-Face-ID connection loop had the same cause.

## Sequence and evidence

1. Owner enabled Tailscale on both devices and Remote Login on the Mac. Phone public key was supplied through the repaired Copy button and authorized. Host public key was verified locally and against the tailnet endpoint.
2. Owner observed Connect → successful Face ID → progress → return to Connect. Earlier generic error handling did not retain the cause. Do not retrospectively assign a transport root cause without an attempt timeline.
3. Introduced attempt-owned lifecycle, independent app unlock, typed startup errors, authentication-success/PTY/remote-exit observations and sanitized device diagnostics.
4. Ran `testPhysicalSSHConnection` on iPhone 15 Pro Max / iOS 26.6. It launched the verified profile, selected SSH, tapped Unlock MoshDeck, then waited for Connect. No unlocked Connect button appeared within 45 seconds. The UI test failed at that exact gate. SSH/PTY/tmux were not attempted by this run.
5. Retrieved only the app's protected connection diagnostic text file. It showed preparation/background-disconnect events and no network stages. No terminal transcript, private key or entire device/application container was retrieved.
6. Separate physical regressions passed for app-lock gating, Ghostty parser/input rendering, and native composer retention across 30 seconds on the Home screen. These three tests do not prove remote connectivity or Face ID success.

## Same-library tests against actual Mac OpenSSH

These opt-in tests use a newly generated temporary Ed25519 identity authorized under a file lock, then remove its exact entry in cleanup. The permanent phone key and other entries are preserved. No personal private key is reused or exported. Tests connect through loopback to the actual Remote Login daemon; this is **not** an iPhone/Tailscale-path measurement.

| Mode | Result | Observed evidence / timing |
| --- | --- | --- |
| Authentication only | PASS | Host pin matched; public-key auth success event; no channel or PTY; one sample 0.139 s |
| Fixed echo, no PTY | PASS | Session/exec accepted, exact MOSHDECK_OK output and exit 0; one sample 0.363 s |
| Clean zsh -f + PTY | PASS | PTY accepted and synthetic command marker returned; one sample 3.333 s including 2 s deliberate pre-input delay |
| Normal login shell + PTY | PASS on extended check | Initial 5 s marker check timed out; extended check returned marker in a 12.536 s run including deliberate delay |
| tmux existing disposable session | PASS | tmux exec accepted; synthetic marker returned; one sample 3.299 s including deliberate delay |

The normal login shell is slower in these samples. This motivates beginning the phone test with the clean-shell diagnostic mode; it does not prove a particular shell startup file caused the original phone loop. No shell configuration or server configuration was changed to make these checks pass.

Mac account membership in the Remote Login access group was verified. SSH directory/file permissions were 0700/0600. A five-minute unified-log query returned no relevant sshd events; lack of logs does not prove absence of authentication attempts. The temporary test authorization entries were verified removed after the tests.

## Current diagnostic and UX behavior

- Unlock MoshDeck establishes a five-minute app session; Connect and Retry do not invoke Face ID during it.
- Connection state and first failure remain visible. Copy Diagnostics includes sanitized stages, numeric/library error categories, attempt IDs, and public-key fingerprint; it excludes terminal output and credentials.
- Authentication-only, echo/no-PTY, clean-shell and normal-shell modes isolate layers. tmux remains a separate option. Codex is excluded until this ladder succeeds on the phone.
- Profile/draft persistence now uses device-only Keychain storage; cold launch starts locked. Cold-launch restoration and unlock policy still need physical acceptance.

## Remaining physical matrix

| Scenario | Status |
| --- | --- |
| Phone app unlock + actual SSH authentication | PASS: manual attempt FDE1FA71, PTY/shell accepted and output received |
| Phone clean shell and live command input/output | PASS by owner report: a couple of commands worked; exact commands/output not captured |
| Phone tmux attachment | PASS: attempt E81EF50E, original pane/shell PID retained |
| Remote terminal background/return | PASS: measured 116.288 s scene-background-to-active interval; automatic foreground trigger, same PID, no new unlock |
| Remote terminal lock 5 min | NOT RUN |
| Wi-Fi → cellular | PASS by owner report; logs show existing connection retained across inactive/active transition; network interface not instrumented |
| Connectivity absent ~1 min and restored | NOT RUN |
| Kill/reopen with saved profile/draft | NOT RUN |
| Real Codex session | Deliberately deferred until raw SSH/tmux succeeds |

For each future run record unlock requirement, SSH reconnect, tmux reattach, retained screen/draft and time to usability separately. A successful fixture, build or Mac loopback test cannot mark these rows passed.

## Highest-value next step

Validate keyboard dismissal on the phone, then run echo hello and uname -a in the connected shell before advancing to tmux. Preserve failure stage and original error if it fails; do not replace the terminal engine or add a backend.

## Confirmed adapter bug and latest build

A new stalled-handshake test initially took 14.8 seconds to return after cancellation. Upstream NIOSSHHandler source shows that channelInactive is consumed instead of forwarded; the adapter's downstream close handler therefore never ran. Observing parent.closeFuture fixed the regression: the full core suite now passes, including the under-two-second cancellation assertion. This validates the closure fix, not the original phone-loop root cause.

The earlier phone build was launched requesting Authentication only, but the routing defect described below meant it actually opened a normal shell. The latest completed core run reported 16 test entries: 15 passed and the opt-in actual-Mac test skipped in the default run. Separate opt-in runs exercised each actual-Mac mode. No temporary interop authorization key remains.

## First physical SSH shell success

After the owner completed app unlock and Connect, the retrieved device timeline recorded attempt `FDE1FA71-A9DC-43AD-B286-61E7D5CEB743`: opening transport, negotiating SSH, host-key match, authentication success, session channel opened, PTY allocated, shell command accepted, then interactive output received. The Ed25519 fingerprint exactly matched the public key previously authorized on the Mac. Connect-to-output elapsed time was 4.466435 seconds in this single sample, excluding app unlock. The app reported connected.

The actual recorded attempt requested a PTY and shell, despite the launch having requested authentication-only mode. This mode mismatch must not be reported as an auth-only test. The mode selector was not wired into intent construction, so this was a normal interactive shell. Intent routing is now centralized and unit tested; additional input/output, tmux and reconnect tests remain required. Mac SSH session activity appeared at the corresponding time. PAM metadata messages alone were not treated as failure because protocol authentication and interactive output succeeded. No terminal transcript or credential was exported.

Several lifecycle defects were fixed before this success (masked first error, Face ID/connection coupling, and incorrect parent-close observation). The original user-visible loop had no retained root trace, so the evidence does not identify a single exclusive original cause. The cancellation/close-signal defect is independently reproduced and regression-tested.


## Keyboard dismissal and expansion regression

On the physical iPhone 15 Pro Max, testTerminalKeyboardDismissalAndExpansion passed: tap the visible synthetic terminal, observe the software keyboard, tap Hide Keyboard, observe keyboard dismissal and a hittable SSH tab, expand, observe accessible Restore controls and Hide Keyboard actions, restore, and verify the SSH tab is hittable again. One test passed with zero failures in 12.253 seconds. The first automation attempt failed to locate the wrapper by accessibility identifier; the corrected test uses the visible fixture coordinate and asserts actual keyboard/tab behavior. This is a fixture UI regression, not proof that a live SSH session survives resizing.

The installed build includes these controls and the diagnostic-intent routing fix. It is reopened with the verified profile and clean interactive shell selected. Core tests reported 15 passed and one explicit opt-in skip; formatting and whitespace checks passed. Live command input and remote resize/reconnect remain manual acceptance gates.


## Owner confirms live commands

The owner reported running a couple of commands successfully in the updated phone build. Retrieved metadata independently records attempt `58B901AA-D0B6-41AD-A256-C0BF830D7FD5` reaching accepted PTY, remote command and interactive output, with a valid app unlock. Connect-to-output was 2.060461 seconds in this single sample. The build had been opened with the corrected clean-shell selection. No command text or terminal transcript was retrieved, so this is owner-reported input/output acceptance, not an assertion that specific commands were independently checked.

The disposable tmux session still exists with pane `%0`, original shell PID 89665, and geometry 80x23 when inspected. Physical phone attachment to it is the next gate. Live expand/restore and the reconnect matrix are not marked passed by the general command-success report.


## First physical tmux attachment and concurrent Mac client

After owner Unlock → Connect, attempt `E81EF50E-3BC4-4982-B72F-9449972F73D3` recorded authentication, accepted PTY, tmux exec acceptance and interactive output. Connect-to-output was 1.887821 seconds in one sample. Mac tmux independently showed the phone client at 37x26 (xterm-256color), pane `%0` at 37x25, and original shell PID 89665. No session was recreated.

A second local Mac PTY client attached at 120x40 while the phone remained attached. Both clients were listed concurrently; the existing latest-client sizing policy changed the pane to 120x39. Closing only that temporary client returned the pane to 37x25 with the phone still attached and PID unchanged. No input was sent to the shared shell and no terminal output was collected. This verifies concurrent phone/local-PTY attachment and detach sizing; it is not an iTerm2 UI or coding-agent acceptance test.

Next physical gate: background MoshDeck for 30 seconds, return within the five-minute unlock window, and verify automatic SSH/tmux reattachment plus interactive use. Long-lock, path-change and offline recovery remain unrun.


### Background/recovery observation in progress

The phone diagnostic subsequently recorded disconnection at Unix time 1788753348.8087811 with its existing unlock deadline still valid. By the follow-up read more than 50 seconds later, no new attempt had appeared and tmux had no attached clients, but pane `%0` and shell PID 89665 remained alive. This confirms detached-session survival during the observed interval. The diagnostic does not label the cause of disconnection, and no owner return-to-app confirmation has arrived, so it does not prove background duration, automatic reconnect, absence of a Face ID prompt, or resumed usability. The recovery row remains pending.


## Recovery with the original tmux process

The owner reported the return workflow was good. Device diagnostics show attempt `8C72BDD8-75E4-4727-8D66-D0181C11CE57` began 98.850476 seconds after the prior disconnect and reached tmux output in 4.247043 seconds. Following another disconnect, attempt `6373C6C9-294D-4C9F-9903-13992731C202` reached tmux output in 2.657403 seconds. Mac metadata independently confirms pane `%0`, original shell PID 89665, and a phone client at 37x14 after recovery. This proves successful reattachment to the retained process and owner-reported usability.

The interval between diagnostic events is not a measurement of exact time backgrounded or foreground-to-usable latency. The app-unlock deadline changed from 03:59:42 to 04:02:40 UTC, so these records cannot support a claim that no additional authentication occurred. Clarification is requested about automatic recovery versus explicit Unlock/Connect. The fixed 30-second/no-repeat-Face-ID acceptance row is therefore not fully passed. Draft retention, five-minute lock, network handover and offline recovery remain separate gates.


Owner follow-up: recovery appeared automatic ("it did connect, I think"). Treat this as tentative automatic-recovery confirmation, not definitive absence of an authentication prompt. A subsequent source change adds sanitized scene transitions, explicit unlock request/success, lock reason, and connect trigger (manual, foreground resume, after app unlock, retry timer). These are fixed local categories without terminal content. They improve evidence on the next installed build; earlier attempts cannot be retroactively classified using them.


The lifecycle-trigger diagnostic build subsequently compiled, installed and launched on the physical phone. This launch supplies only the tmux-mode override, leaving host/user/trust/session fields to the previously saved Keychain profile. Thus successful subsequent connection can also corroborate those profile fields surviving app replacement/relaunch; draft restoration needs its own comparison. Debug launch without a host override opens the Fixture tab, so SSH must be selected. The original Mac tmux shell remains PID 89665. Wi-Fi-to-cellular testing is prepared but not yet run.


## Owner-reported Wi-Fi-to-cellular success

Following instructions to connect, disable Wi-Fi while keeping cellular/Tailscale enabled and try a command, the owner reported success. Attempt `E947583E-9A8B-46A7-93BA-27F733FCF9A4` began with `connect trigger=manual`, reached tmux output in 1.947890 seconds, then recorded scene inactive and scene active 2.353031 seconds apart without a disconnect, a new SSH attempt or another app unlock event. Mac metadata confirms the phone client and original pane `%0` / PID 89665 remain present.

Wi-Fi/cellular interface selection and command output were not independently captured; the network-transition and command-success result is owner-reported. Instrumentation corroborates retained transport across the observed scene transition and no repeated app authentication in that interval. It does not measure keyboard echo latency, cellular packet loss, or prove arbitrary path transitions never require reconnect.

This launch supplied no host/user/trust/session override, so successful authentication and exact tmux attachment corroborate restoration of those saved Keychain profile fields after build replacement/relaunch. Draft restoration is still untested.


Owner clarification: Connect had to be tapped manually; this was acceptable to the owner. Classify the tested workflow as manual connection/reconnection success, not proven automatic recovery. The latest `connect trigger=manual` corroborates the tap. No evidence establishes whether the tap was needed only for initial connection after relaunch or for a subsequent interruption, so neither an automatic-recovery pass nor a specific automatic-recovery defect is asserted. For spike acceptance, manual recovery is currently acceptable to the owner; daily-use automatic recovery remains a separate requirement to validate.


## Current acceptance clarification

The owner explicitly confirmed both recovery success and no Face ID on that recovery. This resolves the earlier uncertainty about the reported retry's authentication experience; it does not retroactively explain every earlier changed unlock deadline. Manual Connect is acceptable for the present spike. Automatic recovery remains an independent behavior to verify, rather than a prerequisite for accepting the demonstrated manual flow.

The next missing lifecycle gate is a deliberate five-minute screen lock followed by authentication and reattachment. Longer lock, reverse cellular-to-Wi-Fi transition, complete outage, draft restoration, full-screen app/agent interaction and device performance measurements remain unverified. Current status is a working physical SSH/tmux spike, not completed daily-use acceptance.


## Instrumented automatic recovery and grace-expiry unlock

Latest owner report: commands worked, app locked, unlocking showed the previous session. Retrieved lifecycle events now independently establish automatic recovery:

- Scene background at 1788753687.443785 closed transport. Scene active at 1788753803.7320318 followed 116.288247 seconds later. Attempt `57E3D8D4-EB3D-4AFC-88B4-28711DEFE054` records `connect trigger=foreground resume` and reached tmux output in 2.340450 seconds from attempt start. No unlock request occurred between these events. This is a measured roughly two-minute background interval, not an exact 30-second run.
- The app recorded `app lock: grace expired` at 1788753889.335281, then unlock request and success. Attempt `230E3823-BFF8-445F-A763-92A784F3F96E` records automatic foreground resume and reached tmux output in 2.607489 seconds from attempt start. Mac metadata still shows pane `%0` and original shell PID 89665.

These traces resolve automatic recovery for the observed background/foreground and post-authentication paths. Manual first Connect after cold launch remains expected. The user's lock/unlock report is successful; the captured lock reason is timer expiry, not an explicit Lock button event, so button invocation is not independently verified by this trace. Five minutes continuously screen-locked, twenty-minute lock and full outage remain separate unrun scenarios. No terminal transcript was collected.

## Daily-use implementation checkpoint — September 7

The accepted spike is preserved in local DCO-signed commits 44a114c (core), 938b1cc (phone harness) and d317f1d (research). Baseline core tests passed (15 plus one opt-in skip); the physical-device-targeted app build passed. This did not rerun the physical acceptance matrix.

Commit 8bf817b implements the new lock policy: authenticated foreground use has no expiry; first inactivity starts five minutes, background preserves that deadline, and foreground return checks expiry before restoring access. A six-test deterministic lock suite was added, including boundary/long-suspension cases. Core total at that checkpoint: 21 passed and one opt-in skip. The build installed, but launch was rejected by CoreDevice because the phone was locked. New-policy physical acceptance is pending; the preserved spike's active timer-expiry trace cannot prove it.

Input hardening is in 8ea2a12: a per-attempt pipe cannot rebind after stop, discards queued/offline callbacks, and resigns the terminal first responder during closure. Suspended fake-writer tests verify old queued data does not reach a replacement connection. Core total: 24 passed and one opt-in skip; the app build including responder resignation passed. Real-device regression remains pending.

| Required MVP scenario | Result | Reconnect / Face ID | Same process | Output timing | Draft / prior screen / error |
| --- | --- | --- | --- | --- | --- |
| Foreground >5 min, new policy | PASS for no unlock expiry: 28m 1.31s connected-to-inactive trace, plus owner report | No intervening relock/auth/disconnect event | PID 89665 remains alive in subsequent Mac check | 1,681.31 s interval | Continuous interaction/typing latency not measured; not a screen-lock test |
| Screen lock >=5 min | PASS: owner confirmation plus 416.27-second background trace | Authentication then automatic foreground reconnect | PID 89665, pane %0 | 2.495 s from reconnect attempt | Composer separately owner-confirmed; exact draft/screen assertions not instrumented |
| Screen lock >=20 min | NOT TESTED | Auth expected | Pending | Pending | Pending |
| Screen lock >=60 min | NOT TESTED | Auth expected | Pending | Pending | Pending |
| Full outage/airplane mode | PASS for recovery: owner confirmed Airplane Mode then 5G | Automatic recovery; no additional app unlock | PID 89665, pane %0 | 38.41 s from initial foreground, network restoration time unknown | Display improved; offline-input/draft assertions not separately observed |
| Wi-Fi → cellular | PARTIAL: owner-reported spike success | No repeat auth in sampled interval; current policy retest pending | Spike same PID | Mixed route, not measured transition latency | Not individually checked |
| Cellular → Wi-Fi | NOT TESTED | Pending | Pending | Pending | Pending |
| Force termination/relaunch | PARTIAL: profile survived build replacement | Cold launch auth; manual Connect | Spike same PID | See sample ledger | Draft/explicit kill test pending |
| Mac unavailable/reachable | NOT TESTED | Actionable failure/retry required | Pending | Pending | Pending |
| Short absence, new policy | PARTIAL: observed 75.27 s absence included Airplane Mode → 5G | Automatic recovery without new app unlock | PID 89665 | Cannot isolate unchanged-network background latency | Owner reports display improved; copy not separately confirmed |
| Explicit Lock, new policy | NOT TESTED | Close/hide, authenticate, restore desire | Pending | Pending | Composer privacy pending |

Real CLI compatibility and performance now have separate [terminal](terminal-compatibility.md) and [performance](performance.md) records. No unrun row is filled from a similar test.

## New-policy phone connection — September 7, 00:49 EDT

The owner reported unlocking and connecting. Retrieved device diagnostics show foreground activation, one successful app unlock, and manual connection attempt `94988E20-DF1A-4530-A222-6B0E033F004C`. Host verification, public-key authentication, channel opening, PTY allocation and tmux command acceptance succeeded. First interactive output arrived 2.243891 seconds after attempt start. The app reported `unlocked(until: nil)`, confirming the foreground-unlimited policy was running. Independent Mac tmux metadata still showed pane `%0`, shell PID `89665`, and size 37×25 in the existing spike session. No terminal contents were collected.

This proves a successful connection under the new lock policy, not six minutes of foreground continuity. That timed test began with this connection and was still pending at this checkpoint. Later input, selection, composer and error-message commits had built but were not installed during this test; do not attribute their acceptance to this run.

## TCP interruption found during owner testing

The owner reported trying commands successfully. A subsequent diagnostic snapshot showed attempt `94988E20` ending with `NIOSSHError.tcpShutdown` classified non-retryable. The next connection was manual; it timed out at authentication, then the existing retry timer successfully attached on attempt `48BD1579` in 5.667810 seconds. No additional app-unlock event occurred in that trace. Independent tmux metadata still showed the original shell PID `89665`. The network/lock actions taken by the owner have not yet been confirmed, so this is not a PASS for a specific roaming or lock-duration row.

Root cause: the NIOSSH error capture branch marked all NIOSSH errors non-retryable, including TCP shutdown. It now allows retry for that precise error type. Regression tests construct the pinned library error and verify retryability plus first-error preservation through cleanup; authentication rejection, host mismatch and invalid authentication signature remain non-retryable. Tests and the iPhone-target build passed. The fix is not yet physically installed/validated. A later diagnostics read was denied, and six uninterrupted foreground minutes remain unproven.

## Recovery-fix deployment — September 7, 00:55 EDT

The full core suite at `4628ff7` reported 32 tests passing, including one skipped opt-in real-Mac test. This includes the new TCP-shutdown classification and 1/10/50 KB input cases. The signed Debug app built and installed on the physical iPhone, retaining the existing bundle identity and Keychain data. It includes all input, selection, composer and failure-message changes through that revision. CoreDevice launch was explicitly denied because the phone was locked. Installation succeeded; physical execution of this build is still pending owner unlock/open.

## Updated-build command acceptance — September 7, 00:59 EDT

After installation of the recovery-fix build, the owner reported a successful echo command check. Retrieved diagnostics show attempt `6E893B53-16DD-4321-8FE4-D13EE8BDA60D` succeeding through host verification, authentication, PTY and tmux attachment, with first interactive output in 2.044113 seconds. App lock was `unlocked(until: nil)`. Mac metadata confirmed the original shell PID `89665` and pane `%0` at 37×13. This is a physical basic command/attachment PASS for the updated build; no command output was collected. Automatic TCP-outage recovery, selection/composer features and uninterrupted foreground-duration acceptance remain separate pending tests.

## Owner-reported recovery with visual instability

The owner reported that “test2” recovered successfully but showed screen flakiness during recovery. The scenario is not yet disambiguated between the earlier numbered outage test and the screen-lock test being discussed; duration, automatic/manual reconnect, authentication and transient versus persistent visual behavior await clarification. Record this as reported recovery with an unresolved visual issue, not a clean PASS for a duration/network row. Mac metadata still showed shell PID `89665`, pane `%0`, at 37×13. The attempted diagnostic retrieval was denied by device file protection, so no new attempt timeline is available for this report. Do not attribute the visual behavior to Ghostty, resizing or transport without reproduction.

## Reconnect view ownership review

Read-only inspection of the pinned wrapper found `TerminalViewRepresentable.configureView` assigns `view.delegate = context` only for initial creation. Its later updates replace the controller/configuration and attach the new state, but do not refresh that delegate. MoshDeck had reused the same SwiftUI view position while replacing TerminalViewState after reconnect. The app now keys TerminalSurfaceView by the terminal state object identity so a replacement state creates its own UIKit view/delegate. The old rendered surface remains selected until the replacement connection is ready, as before.

The iPhone-target build passed. This fixes a concrete stale-delegate risk (including selection callbacks bound to an older attempt); it does not establish the cause of the reported screen flakiness. Physical reconnect, long-press selection after reconnect, keyboard focus and resize need regression checks before claiming a visual fix. The changed build was not installed during the owner’s ongoing lock test.

## Screen-lock and composer acceptance — September 7, 01:14 EDT

The owner confirmed screen-lock recovery and the composer check looked good, and later recalled having performed the foreground check earlier. The foreground report is retained as partial because the exact uninterrupted duration was not established; a repeat is not being requested immediately.

The retrieved trace shows background at 1788757519.077924 and return to active at 1788757935.350079: 416.272155 seconds (6 min 56 sec). The expired background grace was enforced, app authentication succeeded at 1788757948.667827, and automatic foreground-resume attempt `3F29944B-5B23-4E57-9A4D-2E89C2E0B284` produced interactive output in 2.494949 seconds. Independent Mac metadata confirms the same shell PID `89665` and pane `%0`, now 37×25. This passes the at-least-five-minute lock/authentication/automatic-reattach test on the installed recovery-fix build. It does not pass the separate 20/60-minute rows.

Basic composer use is owner-confirmed. The individual 1/10/50 KB, dictation, copy/Unicode, clear/relaunch, draft-after-kill and privacy-cover cases were not separately enumerated and remain pending. Earlier reported display flakiness remains an open visual issue. The terminal-view identity fix is built but still not installed, so this acceptance does not validate that change.

## View-identity fix deployment — September 7, 01:15 EDT

The successful build containing `5582b2a` was installed and CoreDevice launched the app successfully. This supersedes the earlier not-installed note. Requested regression: connect, background for 30 seconds, return, exercise input and long-press Copy, and distinguish transient redraw from persistent corruption. Physical regression results are pending; the earlier screen-lock/composer pass was on the previous build.

## View-identity physical recovery result — September 7, 01:19 EDT

The owner reported recovery was “much better” after installing the view-identity fix. Diagnostics show inactivity from 1788758167.960838 to 1788758243.231370 (75.270532 seconds), TCP shutdown correctly classified retryable, automatic foreground/retry attempts, and no additional app authentication. Several opening-transport timeouts preceded successful foreground-resume attempt `2B6B4958-F9FC-4D09-8AE4-53685C908992`. Output arrived 38.409987 seconds after the first foreground event, or 5.572399 seconds after the successful attempt began. Mac metadata again confirmed PID `89665`, pane `%0`.

Record automatic short-absence recovery and subjective display improvement as passed for this observed run, with slow recovery as an unresolved reliability/performance concern. The actual network-restoration time and route were not measured; the host was also compiling the isolated Ghostty source build. Do not call this a controlled 30-second background benchmark or attribute timeout causes without further evidence. Long-press Copy was requested but not independently confirmed by the owner's general improvement report.

## Clarification: Airplane Mode to 5G

The owner clarified that the improved-recovery test used Airplane Mode and then switched to 5G. This resolves the earlier unknown test conditions for the `2B6B4958` recovery sequence. Record successful full-outage-to-5G recovery, not an isolated unchanged-Wi-Fi background test. The 38.409987 seconds begins at first foreground activation and includes an unknown amount of continued unreachability/network transition. It is not app-only recovery latency or a measured post-restoration SLA. The 5.572399-second successful SSH attempt is separately observable. Offline raw-input rejection, exact outage duration, clipboard behavior and draft retention were not separately confirmed by this result.


## Extended foreground evidence — September 7, 04:39 EDT inspection

Retrieved sanitized device diagnostics still end with the background event at epoch 1788760077.831675. They do not contain a subsequent 20- or 60-minute lock recovery, and those rows remain untested.

The retained earlier attempt `2657037A-0C95-4F60-9250-721A60BC9319` reached interactive output at 1788758375.847423. Its next recorded lifecycle event is `scene inactive` at 1788760057.160598: 1,681.313175 seconds (28 minutes 1.31 seconds). There is no intervening app-unlock, relock, or disconnect event in that attempt timeline. Together with the owner's earlier foreground-check report, this supports the foreground-no-expiry requirement. It does not measure continuous typing, responsiveness throughout the interval, or a locked-phone duration. Independent Mac metadata at inspection still showed pane `%0`, shell PID `89665`, 37×25.

The following foreground-resume attempt `69866380` authenticated, allocated its PTY and received remote-command acceptance, but the channel closed before interactive output and the app returned to background. Do not count that attempt as a successful terminal recovery. Its close/background ordering is recorded without asserting a network root cause.

## VPN reachability and confirmed recovery — September 9

The owner reported repeated connection failures. Attempts through `6DA8E575` closed at `negotiatingSSH` with `disconnected`, before host verification or authentication. At initial inspection the Mac's SSH port accepted local and tailnet-address connections, while Tailscale reported the phone offline and a tailnet ping timed out. This supports investigating VPN availability first; it does not prove the exact cause of each channel closure. No keys or server configuration were changed.

On subsequent inspection Tailscale showed the phone online and answered a ping via DERP in 179 ms. This sample used a relay and did not establish a direct peer path. Retrieved device diagnostics showed two successful foreground-resume attempts:

| Attempt | Attempt to interactive output | Result |
| --- | --- | --- |
| `5202819B` | 2.032 s | Host matched, public-key authentication succeeded, PTY allocated, tmux command accepted, interactive output received |
| `442A53B1` | 2.229 s | Same complete startup sequence; connected at diagnostic capture |

Both attempts reused the valid app unlock without another authentication request. The second followed roughly four minutes inactive/backgrounded, within the five-minute grace. The owner confirmed connecting and that it worked fine. Independent Mac metadata still showed pane `%0`, shell PID `89665`, running zsh. The original server-side shell survived; no replacement session was created for this investigation.

This is a confirmed recovery after the reported connectivity problem, not a controlled 20/60-minute lock, network-direction, draft-retention or typing-latency test. The exact moment VPN reachability returned is unavailable. The initial failures therefore remain correlated with unavailable VPN connectivity rather than a proven SSH-library defect.


## Actual iTerm2 attachment — September 12, 2026

A separate real iTerm2 window was opened with an attach-only command targeting the existing `moshdeck-spike` session. Before attachment tmux reported zero clients, pane `%0`, zsh PID `89665`, and size 37×16. After attachment it reported one xterm-256color client at 171×47 and the same pane/PID at 171×46. The window uses ordinary tmux terminal mode, not iTerm2 control-mode integration. No terminal contents were captured and no command was injected into the shared shell.

The existing window-size policy is `latest`; it was not changed. This proves actual iTerm2 attachment preserves the existing shell and updates its geometry. Phone simultaneous attachment, visible shared output, input from both clients, and detach in both directions remain pending. The owner was asked to connect the phone to this same session, run `echo $$`, and verify `89665` plus shared output in the new Mac window. No response has yet been recorded for that check.


## Required shared-process and switching acceptance — September 12, 2026

The owner explicitly confirmed that simultaneous iTerm2/iPhone control of the same running Codex process and basic phone-side tmux switching are MVP gates. Native tabs and multiple concurrent MoshDeck SSH connections remain excluded. This check supplements, rather than replaces, the outstanding lifecycle/fidelity matrix.

Preparation used a new disposable Git repository under ignored `.build/`, containing only an acceptance README and local instructions. The repository was initialized on branch `acceptance` with a DCO-signed fixture commit. No existing workspace/session was replaced. Actual iTerm2 launched `tmux new-session -A -s work` in that directory. An interactive Codex CLI 0.154.0 process was then launched in its shell with a harmless readiness prompt; the existing ChatGPT login was present. No app-server API, agent internals or terminal transcript collection was used.

Baseline: `work`, pane `%1`, shell PID `36685`, direct child Codex PID `39924`; one actual iTerm2 client attached. A second detached shell session, `moshdeck-switch-check`, was created for the picker test. The older `moshdeck-spike` session remains intact. Process launch does not prove the readiness response was rendered, account execution succeeded, or the phone attached; a possible workspace-trust prompt must be handled in the visible Mac window.

| Step | Required evidence | Current result |
| --- | --- | --- |
| 1. Create/attach `work` in actual iTerm2 | iTerm2 window and tmux client | PASS: actual window plus tmux metadata |
| 2. Start Codex inside `work` | Foreground child process; usable UI | PARTIAL: PID 39924 launched; visible readiness not yet confirmed |
| 3. Attach physical MoshDeck to `work` | Second client, phone live output | NOT TESTED |
| 4. Same running Codex process | Same pane/shell/Codex PIDs with both clients attached | NOT TESTED |
| 5. Phone input reflected on Mac | Harmless prompt/reply visible on both screens | NOT TESTED; owner asked to send a phone marker |
| 6. Mac input reflected on phone | Harmless prompt/reply visible on both screens | NOT TESTED |
| 7. Disconnect phone | Mac remains usable; original Codex PID alive | NOT TESTED |
| 8. Reattach phone, detach iTerm2 | Phone remains usable; original Codex PID alive | NOT TESTED |
| 9. Reattach both | Two clients target original session/pane | NOT TESTED |
| 10. Final continuity | Original shell and Codex PIDs survive | NOT TESTED |
| 11. Phone Ctrl-B then S, switch to second session and back | Picker usable; commands accepted in second shell; original agent survives | NOT TESTED |

Do not type shell PID commands into the Codex prompt. Collect process IDs with Mac-side tmux/process metadata, without capturing terminal contents. After testing a live picker switch, remember reconnect targets the saved `work` profile rather than learning the client's temporary selection. Record the phone build, automatic/manual recovery, lock state, size changes and any input friction with the results. Leave process IDs unchanged until the continuity checks are complete; do not restart the agent merely to get a passing row.


## Phone check report and simultaneous client observation — September 12, 2026

The owner reported “iphone check worked.” Immediate tmux metadata showed two clients on `moshdeck-spike` (171×47 actual iTerm2 and 37×26 phone-sized client), both on pane `%0`, with original zsh PID `89665`. This establishes simultaneous attachment to the same existing shell with the owner's successful phone-check report. The specific visible marker was asked for separately because two checks had been discussed.

At that same observation, `work` had only its 171×47 iTerm2 client, shell PID `36685` and Codex PID `39924`. Therefore this report does not yet establish simultaneous Codex control. The owner was directed to use the phone's Ctrl-B control, type S, select `work`, and send a harmless readiness prompt there. Actual picker success, shared agent output and both directions of detach remain pending.

## Native session panel preparation — September 12, 2026

The layout-only development Release build 2 installed successfully earlier in this session. The subsequent native session panel candidate is build 3, source `91c96c6`. Its Release build and signature check passed, but installation failed with CoreDevice error 1011; a fresh inventory showed the iPhone unavailable. No native-panel physical result is recorded. Connect/unlock the phone, install build 3, then select two existing sessions from **tmux → Switch Session** and verify shared Mac input and selected-target recovery.

At the installation checkpoint, Mac metadata still showed `work` pane `%1`, shell PID `36685`, and the original child Codex PID `39924`. No private terminal output was captured. Process survival does not establish successful phone selection, bidirectional control, detach behavior or layout usability.
