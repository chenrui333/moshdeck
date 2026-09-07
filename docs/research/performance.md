# Performance observations

September 7, 2026. These are observational spike samples, not controlled benchmarks or an MVP performance pass. Physical iPhone 15 Pro Max / iOS 26.6, official Tailscale and actual Mac OpenSSH. No terminal payload logging was used.

## Connection samples

Attempt start to first accepted interactive output, excluding authentication to the application:

| Sample | Workload | Seconds |
| --- | --- | --- |
| FDE1FA71 | Normal SSH shell | 4.466435 |
| 58B901AA | Clean SSH shell | 2.060461 |
| E81EF50E | Initial tmux attachment | 1.887821 |
| 8C72BDD8 | Later tmux attachment | 4.247043 |
| 6373C6C9 | Later tmux attachment | 2.657403 |
| E947583E | Manual tmux connection | 1.947890 |
| 57E3D8D4 | Automatic foreground tmux recovery | 2.340450 |
| 230E3823 | Automatic tmux recovery after authentication | 2.607489 |

For the six tmux observations: min 1.888 s, median 2.474 s, max 4.247 s. These mix first connections and recovery under uncontrolled routes; do not present the aggregate as a controlled roaming benchmark. The two shell observations are not aggregated with tmux.

For 57E3D8D4, scene-active to output was 2.345287 s. The recorded background-to-active interval was 116.288247 s. Authentication duration and exact phone screen-lock state are separate measurements. Mac-to-phone DERP probes previously sampled 158–242 ms, which is neither keyboard echo nor proof of the route used by each attempt.

## Component baseline

The preservation checkpoint reran the exact 1 MiB Mac loopback OpenSSH transfer in 0.167126 s. This excludes phone networking and Ghostty rendering. The test also verifies all payload bytes and Ctrl-C afterward. It cannot support a device throughput claim.

## Missing device measurements

| Metric | State | Next measurement |
| --- | --- | --- |
| Implementation-build connection/recovery | Observed, uncontrolled: see below | Repeat per controlled scenario; separate network restoration and app unlock |
| Typing/echo | NOT TESTED | Subjective observation plus controlled echo timing if needed |
| Redraw/scrollback/resize | NOT TESTED | Ordinary full-screen tasks and moderate output |
| CPU/memory/thermal | NOT TESTED | Instruments during meaningful active session and output |
| Battery | NOT TESTED | Device/brightness/network/workload duration recorded |
| Composer 1/10/50 KB | NOT TESTED | Interaction, completion and duplication checks |
| Existing mature client | NOT TESTED | Same host/tmux and network if client available |

No new transport or renderer is justified by these limited observations. Investigate stage-specific regressions before optimization. Source rebuild/compiler performance is not terminal runtime performance.

## Implementation-phase phone observations

| Attempt | Conditions | Attempt to interactive output |
| --- | --- | --- |
| 94988E20 | First connection with foreground-unlimited lock policy | 2.243891 s |
| 6E893B53 | Updated TCP-recovery build, owner echo check | 2.044113 s |
| 3F29944B | Automatic reconnect after 416.27-second lock and app authentication | 2.494949 s |
| 2B6B4958 | Successful attempt after Airplane Mode, then 5G | 5.572399 s |

Across these four mixed observations: min 2.044 s, median 2.369 s, max 5.572 s. They span builds and network conditions and are not a controlled comparison. The outage-to-5G sequence took 38.409987 seconds from its first foreground event to output, including retries while the Mac was unreachable; the exact restoration time is unknown. Do not label that interval app reconnect overhead. The Mac was also running an isolated dependency build during the last observation. The owner reported the recovery display was much better with the view-identity fix; this is subjective visual acceptance, not frame-timing evidence.
