# TestFlight beta

On September 9, the owner authorized preparing a TestFlight beta using `asc`, with further physical acceptance collected through beta testing. This does not mark the daily-use MVP or the remaining lifecycle matrix complete. Git pushes and production App Store submission are not part of this checkpoint.

## Current distribution — build 4, September 16, 2026

Version **0.0.1 (4)** is processed **VALID** and **IN_BETA_TESTING** for the existing internal **Personal Beta** group. Build ID: `c4389b8c-24c7-4759-9ab2-a5664bb513b9`. Group ID: `ed5379bd-32f5-4e5c-a22e-626df71dd3a0`.

After the owner completed Xcode account setup, the preserved build-4 archive exported successfully using automatic signing. No app source changed. The IPA passed strict signature verification, has `get-task-allow=false` and `beta-reports-active=true`, has no provisioning device list, and contains all 10 matching license notices. IPA SHA-256: `96814b25ba2d2203882b8c7b5c8f4b265b5c1eff221decd425568db4b4f8fa56` (7,867,435 bytes).

The upload reservation dry run succeeded, followed by the actual upload. Apple accepted upload `c4389b8c-24c7-4759-9ab2-a5664bb513b9` and reported PROCESSING. The CLI's 60-second discovery wait expired after upload commit; subsequent checks follow the existing upload, without uploading a duplicate. The API supplied no upload checksums, so the requested API checksum comparison was unavailable; the local SHA-256 and signature checks above are independent evidence.

Processing subsequently completed. The existing audited encryption declaration (`usesNonExemptEncryption=false`) was applied, and the en-US What to Test text matches [beta-test-notes.txt](beta-test-notes.txt), apart from its trailing newline. API readbacks confirmed explicit Personal Beta membership and internal testing status. External state remains READY_FOR_BETA_SUBMISSION; no external review, public link, or production App Store submission was initiated. No Git push was performed.

Direct physical checks remain waived for this iteration. Simulator and local integration results are recorded below; gesture acceptance remains pending beta feedback.

### Local follow-up after build 4

The in-app Shared sessions help now explains native picker/swipe switching and its confirmed reconnect-target update, separately from the manual tmux picker. Build 4 still contains the older manual-only help text; this copy correction is local source for the next build, not part of the distributed IPA. No connection or input behavior changed. Strict Swift formatting, whitespace validation and an arm64 Release simulator build passed. Updated [phone test steps](research/phone-test-steps.md) cover native switching, Mac-client isolation and shared-process checks without treating the hardware waiver as a pass.

## Previous distribution — September 12, 2026

Version **0.0.1 (1)** is uploaded, processed **VALID**, and **IN_BETA_TESTING** for the internal **Personal Beta** group. The owner is the sole tester and is **INVITED**; installation through TestFlight has not yet been confirmed. External state is **READY_FOR_BETA_SUBMISSION**: no external beta review or public invitation link exists yet.

- App Store Connect app: `6811461068`.
- Build: `5aaca512-d147-4f90-9bdd-9b3c6ae0c875`.
- Internal group: `ed5379bd-32f5-4e5c-a22e-626df71dd3a0`.
- Uploaded IPA SHA-256: `e210f61cd329ddb43ae012cc17447f6f193141b1e3c790121b563509be498142` (notice-inclusive archive after `5000793`).
- What to Test: the original build-1 en-US localization was saved and verified by the API response. The repository [beta-test-notes.txt](beta-test-notes.txt) now contains the build-4 instructions; the original build-1 localization remains historical.
- Encryption metadata: `usesNonExemptEncryption=false`, accepted by App Store Connect. The declaration uses the audited Apple-platform CryptoKit implementation described below and Apple's OS-provided encryption documentation category. Tailscale is external to this app. The build Info.plist remains unchanged; the declaration was recorded on the processed build.

Readbacks confirmed the build/group relationship and internal testing state. No production App Store submission or Git push was performed. This distribution checkpoint does not complete the remaining physical acceptance matrix. Historical preparation notes below describe superseded artifacts and earlier gates.

## Initial preparation checkpoint — September 9

- Source: `29f459b`; version 0.0.1, build 1.
- Bundle identifier: `com.chenrui333.MoshDeckSpike`, retained to preserve the existing application identity.
- App Store Connect API authentication works. The explicit bundle identifier was registered successfully.
- No MoshDeck app record existed at inspection. The Apple web session needs fresh authentication before first-record creation through `asc web apps create`.
- Release archive and App Store Connect distribution export both succeeded. Export is preparation, not an uploaded or processed TestFlight build.
- IPA SHA-256: `20260bb66ae6ff05e8dc4d29c751534b864f7d64bab9cc0fbbf73e9be9a3f816`.
- Existing core regression run reported 32 tests, including the opt-in integration skip. Physical connectivity recovery is recorded in [device findings](research/physical-device-connection-debug.md).

Archives, exported IPA, provisioning material and raw signing logs remain outside Git. The installed physical-phone build was not replaced during this preparation.

## Original pre-upload checklist (completed; retained as history)

1. Create the App Store Connect record with the existing bundle identifier after secure local web authentication. Do not put Apple passwords or two-factor codes in chat or repository files.
2. Re-archive with the beta icon added after the initial export; that earlier IPA has no `CFBundleIcons` entry.
3. Complete the encryption declaration for the actual SSH implementation; the archive does not set `ITSAppUsesNonExemptEncryption`.
4. Integrate and validate the tested conditional-libintl candidate through a reproducible dependency path, or resolve the current artifact's static-link distribution obligations. The candidate passes device consumer build and two simulator fixtures, but the app still pins the original binary. Complete the remaining inventory in [licenses](research/licenses.md). Successful signing does not resolve these requirements.
5. Rebuild/export the final source, verify distribution entitlements and signature, upload with `asc`, and inspect processing before assigning a tester group. Tester invitations are a separate explicit action.

## Initial beta scope

The tested remote workflow is official Tailscale, ordinary macOS OpenSSH, Ed25519 phone identity, strict host-key verification and an existing tmux session. Tailscale is the supported deployment recipe, not an embedded dependency or hard network requirement. Local-network or other VPN access may work through ordinary SSH but has not received the same device acceptance.

What to Test should focus on connection setup, terminal input, composer, keyboard dismissal, background/lock recovery and preservation of the same tmux process. Keep the separate 20/60-minute lock, network-direction, termination, broader terminal and real coding-agent dogfood rows pending until observed. No backend, account system, Mosh transport or agent API is included.

## Beta icon checkpoint

Added an original geometric terminal icon and MoshDeck display name, preserving the bundle identifier. The reproducible generator is `Spike/scripts/generate-app-icon.swift`. Its initial 24-bit AppKit drawing context failed; the corrected generator uses a 32-bit Quartz context with no alpha channel. The resulting PNG is 1024×1024 and was visually inspected. A Release device-target build succeeded and its generated Info.plist contains both iPhone and iPad primary-icon entries. The earlier exported IPA has not been replaced or uploaded.

## Encryption implementation evidence

The first arm64 Release archive links Apple's system CryptoKit and Security frameworks. Its undefined-symbol table includes CryptoKit references. In the pinned Swift Crypto 4.5.2 package, the ordinary Apple-platform `Crypto` API re-exports CryptoKit; NIOSSH's AES-GCM transport implementation calls that API. Earlier Release link-map inspection found no BoringSSL object references. MoshDeck therefore must not be described as shipping a separate BoringSSL implementation merely because Swift Crypto contains one for other targets.

The app still implements SSH protocol handling through SwiftNIO SSH and intentionally provides encrypted remote terminal access. Official Tailscale is a separate installed VPN application and is not shipped in this binary. These are the facts to use for App Store Connect's encryption questionnaire; this checkpoint does not assert that the entire app automatically qualifies as OS-only encryption or set an exemption flag without completing that determination.

Apple's current [export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/) requires a determination for encrypted beta distribution and provides a questionnaire based on implementation and intended availability. Its [documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption) distinguishes Apple-OS crypto from separately implemented standard algorithms. Complete the questionnaire for the actual build and distribution scope before recording the final Info.plist declaration. References checked September 9, 2026.

## Local dependency preparation recipe

`python3 Spike/scripts/prepare-ghostty.py` prepares a local Swift package under ignored `.build/ghostty-ios/package` on an Apple Silicon Mac with Zig 0.16.0, Xcode and its Metal toolchain installed. It fetches exact wrapper/core commits, applies the upstream patch stack and conditional-libintl patch, builds arm64 device and simulator libraries, rejects gettext symbol matches and writes `provenance.json` with tool versions and artifact hashes. Use `--output` for a different fresh destination. The script refuses to overwrite an existing directory, including a failed run, so evidence is preserved. Native build output and source checkouts are not committed.

The complete fresh-checkout validation passed on September 9: both native libraries, gettext symbol checks and XCFramework packaging completed successfully. The main project still references the upstream binary package; writing this recipe does not change that reference or establish that a beta uses the candidate.

## Source package integrated

The project now consumes `.build/ghostty-ios/package`, generated by the pinned preparation recipe. Both selected simulator terminal tests passed against this fresh package (two tests, zero failures), and a signed Release archive succeeded with the icon present and no gettext symbol matches in the final executable. The original downloaded-XCFramework archive/IPA described above is superseded for further beta work; neither was uploaded. This source-built archive still needs distribution export and final metadata/attribution checks. The installed phone app has not been replaced, and physical regression remains pending.

## Source-built distribution export

The integrated source-built archive exported successfully as version 0.0.1 (1). IPA size: 7,751,583 bytes; SHA-256 `09c8e14ea09848d5214820054d1e2214e2174b543903464a66dd823252f0540c`. The extracted application passed `codesign --verify --deep --strict`. Its signature has `get-task-allow=false` and `beta-reports-active=true`; the distribution provisioning profile has no device list. The exported executable has no gettext symbol matches. These checks supersede the first export's binary evidence, but do not imply an Apple upload or processing result.

Apple web authentication remained unavailable at this checkpoint. App-record creation, encryption declaration, remaining resource attribution and beta metadata remain unfinished. No testers have been invited and nothing has been uploaded.

## Latest notice-inclusive export

Archive/export after `5000793` succeeded. IPA SHA-256: `e210f61cd329ddb43ae012cc17447f6f193141b1e3c790121b563509be498142`. The extracted application passed strict signature verification; `Seti-MIT.txt` and `AdditionalSymbolFonts.txt` match their repository files byte for byte. This supersedes earlier candidate IPA hashes for upload preparation. Apple web authentication is still pending, so there is no app-record creation, upload, processing result or tester distribution.

## Build 2 preparation — September 12, 2026

Source `f1a9643` sets version 0.0.1 (2) and includes session help. The signed Release archive and App Store Connect distribution export succeeded. The original archive command referenced a deleted temporary dependency checkout; reusing the current validated package cache resolved that preparation error. Export then failed because Apple's rsync started Homebrew rsync 3.5.0, which rejected `--extended-attributes`; using a system-tools-only PATH for the export command succeeded without machine-wide changes.

Build 2 has not been uploaded or distributed. Export verification and upload remain pending while the owner reviews the newly requested layout investigation. The exported artifact still contains the current Fixture navigation; the layout document recommends removing it from Release in a subsequent implementation, not pretending that change is already in this archive. Internal TestFlight build 1 remains the current available beta.

## Layout build supersedes the earlier candidate

The archive/export from `f1a9643` predates the compact layout and is superseded for the next beta. Do not upload it as the layout build. Source `c90efdd` built and installed as development-signed Release 0.0.1 (2) on the paired iPhone; physical layout acceptance remains pending. This installation is not a TestFlight distribution. Re-archive/export the accepted layout source before uploading build 2. Internal TestFlight build 1 remains unchanged.

## Native session panel candidate — build 3

Source `91c96c6` includes the native tmux side panel and sets version 0.0.1 (3). The development-signed Release build and strict signature verification passed. Installation failed because the paired iPhone became unavailable to CoreDevice; build 2 remains the last successfully installed device build. Build 3 has not been archived/exported for distribution, uploaded or added to TestFlight. Internal build 1 remains unchanged. The superseded build-2 export must not be mistaken for the native panel candidate.

## Build 3 archive verification — source `066ab4b`

The signed Release archive completed successfully. Its application identifies as 0.0.1 (3), retains the existing bundle identifier and includes its icons. Strict signature verification passed; all 10 repository notice files match their bundled copies. Synthetic fixture markers and gettext imports are absent from the archived executable. Executable SHA-256: `ef7c879f78eaac0a52e808a67a11c553fb9f43bb7edfb8780041ba59ce99a987`. This verifies the archived application, not an exported distribution IPA.

Distribution export failed with **No Accounts** and **No signing certificate "iOS Distribution" found**. Inspection of the prior successful export confirms that it used Apple's remote/cloud-managed Distribution signing, while the local keychain currently exposes one Apple Development identity. The initial preference check established only that the Apple ID list key existed; it did not establish that an account was configured. A subsequent inspection found that its account array was empty. No certificate was created, revoked or replaced. The owner was asked to refresh the Xcode account session before export is retried.

The paired phone also remains unavailable to CoreDevice, so installation and physical testing of build 3 are still pending. These are separate gates: the development build can be installed once the phone is reachable; distribution export needs the signing account session. No build-3 IPA, upload, processing result or TestFlight assignment is claimed.

The repository What to Test draft now describes build 3's compact layout and native panel. It has not been sent to App Store Connect and does not replace the existing build-1 localization remotely.

### September 13 device update

Development Release build 3 is now installed and launched on the iPhone 15 Pro Max. Fresh device diagnostics confirm an unlocked app and a connected attempt with interactive output. The native panel acceptance sequence remains pending. A distribution-export reattempt still failed with the account/signing-session errors above; nothing new was uploaded or assigned in TestFlight.

### Signing blocker clarification — September 13

A structural inspection of Xcode's `DVTDeveloperAccountManagerAppleIDLists` preference found one dictionary entry containing an **empty account array**. No account credentials or scalar values were printed. This corrects the earlier inference from the mere presence of that preference key: there is no configured Apple ID in this list for automatic/cloud-managed distribution signing. Add the owner account through Xcode → Settings → Accounts before retrying export. The prior successful cloud-signing export remains valid historical evidence; no new Distribution certificate or key should be created merely because the current local keychain lists only a Development identity.


## Hybrid session-switch beta — build 4, September 13

Source `2bc02fe` is archived as 0.0.1 (4), containing interactive horizontal session switching and a visible Sessions picker. The underlying switch uses only the existing phone tmux client and SSH transport. The owner explicitly waived direct hardware checks for this iteration and requested TestFlight distribution afterward; physical acceptance remains pending beta feedback.

Verification passed: 40 core tests, the strengthened seven-test isolated OpenSSH suite, four targeted Debug simulator tests (swiping/scroll/selection, picker, keyboard/rotation, composer background draft), maximum Dynamic Type picker access, and Release locked startup without Fixture navigation. The Release simulator command requires `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` for the current arm64 terminal artifact; the first unrestricted command attempted unsupported x86_64 linkage and failed. This is not a physical-device result.

The signed archive passed strict codesign verification; all 10 license notices match their repository sources, synthetic fixture markers are absent, and no gettext imports were found. Archived executable SHA-256: `963705b3b226f82eab6763c7c0727341ee44e1541409833c5baf0671cdc8d6a2`.

**Historical signing gate (resolved September 16 above).** Supplying the existing API credential explicitly allowed a fresh ASC build query, which still returned only build 1 in VALID processing state. Xcode's supported API-key cloud-signing export was then attempted, but returned **Cloud signing permission error** and **No signing certificate "iOS Distribution" found** (exit 70). This refines the earlier No Accounts diagnosis: an API-key route exists, but the current credential could not cloud-sign this export. Xcode's configured account list remains empty; the owner was asked to sign in through Xcode Settings → Accounts. No certificate, API role, or account permissions were altered.

At that September 13 checkpoint there was no build-4 distribution IPA or upload. The build-4 What to Test text in `beta-test-notes.txt` is ready but has not been applied remotely. After signing is available, export the preserved archive, verify the IPA's version/bundle/signature and notices, reserve/inspect its upload with `asc builds upload --dry-run`, upload it, wait for processing, apply encryption metadata and test notes, and assign the existing internal Personal Beta group. Do not upload superseded build-2 or build-3 artifacts.
