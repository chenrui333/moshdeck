# SSH library decision

Source inspection: 2026-09-06. The spike targets one controlled modern macOS OpenSSH host, not every SSH appliance. All listed libraries still need application-level host trust, Keychain storage, reconnect policy and lifecycle integration.

| Candidate | Strengths | Gaps / maintenance | Decision |
| --- | --- | --- | --- |
| [libssh2](https://github.com/libssh2/libssh2) | Mature C client, nonblocking API, known_hosts support, public key/password/keyboard-interactive, agent and signing callbacks, PTY/resize/keepalive | Latest published release observed: 1.11.1 (2024-10-16); main is 1.11.2_DEV. Need Apple XCFramework and crypto backend build; C lifetime/EAGAIN/partial-write handling | Best alternate for broad interoperability |
| [libssh](https://www.libssh.org/) | Maintained C client/server, SSH configuration and proxy/agent features, PTY and modern algorithms | Client/server surface larger; LGPL static-link/distribution work; crypto packaging | No compelling advantage for this narrow client |
| [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh/tree/3ec281496f28a3b6581afd946b759e2642f5cd8d) | Apple upstream, version 0.15.0 released July 2026, channel flow control, Ed25519/ECDSA, X25519, AES-GCM, explicit server-auth delegate | Building blocks, not OpenSSH compatibility layer; no turnkey ssh_config/private-key import/agent UX | Selected for spike |
| [NMSSH](https://github.com/NMSSH/NMSSH) | Familiar Objective-C wrapper around libssh2; iOS heritage | Last upstream commit observed August 2018; wrapper/backend modernization burden | Reject as starting point |
| [Citadel](https://github.com/orlandos-nl/Citadel) | Async high-level PTY APIs, key parsing, jump connections, SFTP | Inspected manifest depends on Wellz26 NIOSSH fork, BigInt and bcrypt; unsafe validator appears in example with warning | Do not inherit extra fork/algorithm surface without a requirement |
| SwiftTermApp / SwiftSH and similar wrappers | Real iOS connection examples | Verify exact underlying libssh2/crypto versions and wrapper maintenance before copying | Reference implementations; no unverified binary bundle |
| Blink's SSH code | Real shipping mobile behavior | GPL app code and bundled framework provenance; not a permissive drop-in | Study behavior; no source copied |

## Required capability matrix

| Capability | libssh2 | libssh | Selected NIOSSH |
| --- | --- | --- | --- |
| Ed25519 | Yes, depends on crypto build | Yes, crypto/version dependent | Yes, direct key construction |
| Host verification | Host-key bytes and known_hosts helpers; caller enforces | Known-server APIs; caller enforces | Delegate must reject unknown/mismatched key until authorized |
| Keychain | App responsibility | App responsibility | Store generated Ed25519 material with device-only protection |
| Secure Enclave | Signing callback can be adapted; not turnkey | Custom signing integration needs proof | Current `NIOSSHPrivateKey(secureEnclaveP256Key:)` exists on Darwin; device proof required |
| Keyboard-interactive | Yes | Yes | Not an MVP-supported auth method; do not substitute password |
| Agent support | Agent API | Agent API | No turnkey agent client/forwarding in inspected public feature set |
| Proxy/jump | App transports/tunnel plumbing | Configuration/proxy support | DirectTCPIP building blocks; app must implement jumps |
| ssh_config | No full OpenSSH parser | Supported subset | No parser; explicit host profile only |
| PTY/resize | Channel APIs | Channel APIs | `PseudoTerminalRequest`, `WindowChangeRequest` |
| Keepalive | Explicit APIs | APIs/configuration | App schedules a protocol-level liveness request/deadline; no terminal text probes |
| Reconnect | New connection and channels | New connection and channels | New connection and channels; never resumes old TCP stream |
| Swift concurrency | Wrap C on owned serial executor | Same | Event-loop ordering + async bridge; do not make Channel handlers main-actor objects |

[libssh2 header](https://github.com/libssh2/libssh2/blob/master/include/libssh2.h) exposes memory key loading, known-host checking, signing and keepalive. [NIOSSH README](https://github.com/apple/swift-nio-ssh/blob/3ec281496f28a3b6581afd946b759e2642f5cd8d/README.md) describes its protocol scope. [Private-key API](https://github.com/apple/swift-nio-ssh/blob/3ec281496f28a3b6581afd946b759e2642f5cd8d/Sources/NIOSSH/Keys%20And%20Signatures/NIOSSHPrivateKey.swift) provides Ed25519 and Secure Enclave P-256 initializers. An Enclave key is **not Ed25519**, is not an imported SSH key, and must be tested with device lock/biometric signing and server negotiation.

## Selection constraints

Start with a newly generated per-phone Ed25519 identity, avoiding a private-key file parser entirely. Export only its OpenSSH-format public key to the owner for installation. Existing encrypted OpenSSH private-key import, RSA-only servers, keyboard-interactive/2FA, agent forwarding and ProxyJump are explicitly deferred. If real daily usage requires those, reconsider libssh2 rather than growing ad-hoc protocol implementations.

Compare host-key identity before offering user credentials, with explicit initial verification and a hard stop on changes. Pin full public-key identity scoped to hostname and port, render SHA-256 fingerprint for review, and require a separate re-enrollment flow to replace trust. Do not use `.acceptAnything()` or the permissive delegate from an example.

SSH compression is optional and unnecessary for the first mobile terminal. No DSA, SHA-1 RSA signatures or obsolete cipher fallback. Crypto capability lists depend on the shipped build, so verify actual negotiation against the Mac and audit advisories for every pinned release before shipping. Native Swift and a well-known upstream are not substitutes for that work.

## Current security advisories checked

The selected versions are deliberately above the published fixes; algorithm restriction is not a substitute for these updates.

| Advisory | Published issue | Fixed in | Selected |
| --- | --- | --- | --- |
| [GHSA-998x-vgvp-xwpc](https://github.com/apple/swift-nio-ssh/security/advisories/GHSA-998x-vgvp-xwpc) | Pre-authentication ECDSA signature parsing stack overwrite, including clients | NIOSSH 0.14.1 | 0.15.0 |
| [GHSA-r3rc-9hpw-54v9](https://github.com/apple/swift-nio/security/advisories/GHSA-r3rc-9hpw-54v9) | ByteBuffer index/length overflow | NIO 2.100.0 | 2.102.0 |
| [GHSA-8q93-f6xh-4f6f](https://github.com/apple/swift-crypto/security/advisories/GHSA-8q93-f6xh-4f6f) | Double-free when parsing malformed RSA public keys | Swift Crypto 4.5.1 | 4.5.2 |

The first advisory states that a malicious peer selects the signature format before verification; accepting only an Ed25519 host identity would not have protected a vulnerable parser. The Crypto RSA path is not needed by this app, but the selected package also includes its fix. These checks cover identified published advisories, not a complete security audit or assurance of no unknown vulnerabilities.

The component spike now uses an authenticated SSH session-channel open/close for liveness. It executes no command and writes no terminal bytes. This works around the lack of a public generic global-request sender without forking NIOSSH; servers must permit an additional temporary session channel. The local OpenSSH test exercises it. Device behavior, server session quotas and timer tuning remain open.
