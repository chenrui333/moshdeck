import Foundation
import GhosttyTerminal
import LocalAuthentication
import MoshDeckCore
import Security
import SwiftUI
import UIKit

// The spike has a single profile and active connection; no host browser/framework.
@MainActor
private enum PhoneIdentityStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.chenrui333.MoshDeckSpike",
        kSecAttrAccount as String: "ssh-ed25519",
    ]

    static func loadOrCreate() throws -> SSHIdentity {
        var lookup = query
        lookup[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return try SSHIdentity(privateKeyRepresentation: data)
        }
        guard status == errSecItemNotFound else { throw IdentityError.keychain(status) }
        let identity = try SSHIdentity()
        var insert = query
        insert[kSecValueData as String] = identity.privateKeyRepresentation
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let saved = SecItemAdd(insert as CFDictionary, nil)
        guard saved == errSecSuccess else { throw IdentityError.keychain(saved) }
        return identity
    }

    static func profile() -> Data? {
        var q = query
        q[kSecAttrAccount as String] = "session-profile"
        q[kSecReturnData as String] = true
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess else { return nil }
        return value as? Data
    }
    static func saveProfile(_ data: Data) throws {
        var q = query
        q[kSecAttrAccount as String] = "session-profile"
        let updated = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw IdentityError.keychain(updated) }
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(q as CFDictionary, nil)
        guard result == errSecSuccess else { throw IdentityError.keychain(result) }
    }

    enum IdentityError: Error { case keychain(OSStatus) }
}

@MainActor
final class RemoteTerminalModel: ObservableObject {
    @Published var host = ""
    @Published var username = ""
    @Published var port = "22"
    @Published var trustedHostKey = ""
    @Published var sessionName = "moshdeck-spike"
    @Published var tmuxPath = "tmux"
    @Published var useTmux = false
    @Published var diagnosticMode = "clean-shell"
    @Published var createSession = false
    @Published var publicKey = ""
    @Published var draft = ""
    @Published var terminal: TerminalViewState?
    @Published var selection: TerminalSelectionSnapshot?
    @Published var pasteWarning = false
    @Published private(set) var lifecycle = ConnectionLifecycle()
    @Published private(set) var appLock = AppLockPolicy()
    @Published var notice = ""
    private var connection: SSHConnection?
    private var input: TerminalInputPipe?
    private var connectTask: Task<Void, Never>?
    private var livenessTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var lockTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<ConnectionEvent>.Continuation?
    private var previousAttempts: [String] = []
    private var candidate: TerminalViewState?
    private var sceneActive = true
    private var desiredActive = false
    private var retryIndex = 0
    private var pendingPasteAttempt: UUID?
    private var presentedAttempt: UUID?
    private var activeIntent: SessionIntent = .shell
    private let retryDelays = [0, 1, 2, 5, 10]

    var unlocked: Bool { appLock.permitsAccess(at: Date()) }
    var preparingKey: Bool { appLock.state == .unlocking }
    var isLive: Bool { lifecycle.isLive && unlocked && sceneActive }
    var busy: Bool { lifecycle.isStarting || retryTask != nil }
    var status: String {
        if !unlocked { return preparingKey ? "Unlocking app…" : "App locked" }
        switch lifecycle.state {
        case .idle, .cancelled: return "Ready"
        case .starting(let stage): return stage.title + "…"
        case .connected: return "Connected"
        case .reconnecting(let index): return "Reconnecting (\(index + 1))…"
        case .disconnected: return "Disconnected — remote tmux work continues"
        case .failed(let failure): return "\(failure.title)\n\(failure.message)"
        }
    }

    // Keep automation independent of the human-readable, stage-specific error text.
    var accessibilityConnectionState: String {
        guard unlocked else { return preparingKey ? "Unlocking" : "Locked" }
        switch lifecycle.state {
        case .idle: return "Idle"
        case .cancelled: return "Cancelled"
        case .starting: return "Connecting"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        }
    }

    private struct SavedSession: Codable {
        var host: String
        var username: String
        var port: String
        var trustedHostKey: String
        var sessionName: String
        var tmuxPath: String
        var draft: String
        var useTmux: Bool
        var diagnosticMode: String
    }
    init() {
        if let data = PhoneIdentityStore.profile(), let saved = try? JSONDecoder().decode(SavedSession.self, from: data)
        {
            host = saved.host
            username = saved.username
            port = saved.port
            trustedHostKey = saved.trustedHostKey
            sessionName = saved.sessionName
            tmuxPath = saved.tmuxPath
            draft = saved.draft
            useTmux = saved.useTmux
            diagnosticMode = saved.diagnosticMode
        }
        #if DEBUG
            let env = ProcessInfo.processInfo.environment
            host = env["MOSHDECK_SPIKE_HOST"] ?? host
            username = env["MOSHDECK_SPIKE_USER"] ?? username
            trustedHostKey = env["MOSHDECK_SPIKE_HOST_KEY"] ?? trustedHostKey
            sessionName = env["MOSHDECK_SPIKE_SESSION"] ?? sessionName
            tmuxPath = env["MOSHDECK_SPIKE_TMUX"] ?? tmuxPath
            if let mode = env["MOSHDECK_SPIKE_MODE"], ["auth", "echo", "clean-shell", "shell"].contains(mode) {
                diagnosticMode = mode
                useTmux = false
            } else if env["MOSHDECK_SPIKE_MODE"] == "tmux" {
                useTmux = true
                createSession = false
            }
        #endif
    }

    func saveSession() {
        guard unlocked else { return }
        do {
            let value = SavedSession(
                host: host, username: username, port: port, trustedHostKey: trustedHostKey,
                sessionName: sessionName, tmuxPath: tmuxPath, draft: draft, useTmux: useTmux,
                diagnosticMode: diagnosticMode)
            try PhoneIdentityStore.saveProfile(JSONEncoder().encode(value))
        } catch { notice = "Could not save the profile/draft in Keychain." }
    }
    func unlock() async {
        guard !preparingKey else { return }
        if unlocked { return }
        lifecycle.note("app unlock requested")
        persistDiagnostics()
        appLock.beginUnlock()
        do {
            let context = LAContext()
            guard
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Unlock MoshDeck remote terminal access")
            else {
                appLock.failed()
                return
            }
            guard UIApplication.shared.applicationState != .background else {
                appLock.lock()
                return
            }
            appLock.unlocked(at: Date())
            lifecycle.note("app unlock succeeded")
            persistDiagnostics()
            notice = "App unlocked. Authentication is required after five minutes away or explicit Lock."
            scheduleBackgroundLock()
            if desiredActive && sceneActive { connect(trigger: "after app unlock") }
        } catch {
            appLock.failed()
            notice = "App unlock failed (LocalAuthentication code \((error as NSError).code)). Try Unlock again."
            lifecycle.note("app unlock failure code=\((error as NSError).code)")
            persistDiagnostics()
        }
    }

    private func scheduleBackgroundLock() {
        lockTask?.cancel()
        lockTask = nil
        guard !sceneActive, let deadline = appLock.deadline else { return }
        let delay = max(0, deadline.timeIntervalSinceNow)
        lockTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !self.sceneActive, self.appLock.deadline == deadline else { return }
            if !self.appLock.permitsAccess(at: Date()) { self.lock(reason: "background grace expired") }
        }
    }

    func lock(reason: String = "owner requested") {
        lifecycle.note("app lock: \(reason)")
        saveSession()
        appLock.lock()
        selection = nil
        lockTask?.cancel()
        lockTask = nil
        stopTransport()
        lifecycle.stop()
        persistDiagnostics()
    }

    func prepareKey() async {
        guard unlocked else {
            notice = "Unlock the app first."
            return
        }
        do {
            publicKey = try PhoneIdentityStore.loadOrCreate().publicKey
            notice = "Public key ready."
        } catch { notice = "Keychain could not load the phone identity." }
    }
    func copyPublicKey() {
        guard unlocked, !publicKey.isEmpty else { return }
        UIPasteboard.general.string = publicKey
        notice = "Public key copied."
    }
    func copyDiagnostics() {
        UIPasteboard.general.string = diagnostics
        notice = "Sanitized diagnostics copied."
    }
    private var diagnostics: String {
        "appLock: \(appLock.state)\n" + (previousAttempts + [lifecycle.diagnostics]).joined(separator: "\n\n")
    }
    private func persistDiagnostics() {
        // Fixed stages/error categories only. No host/user names, keys or terminal data.
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? diagnostics.data(using: .utf8)?.write(
            to: root.appendingPathComponent("connection-diagnostics.txt"), options: [.atomic, .completeFileProtection])
    }

    func connect(automatic: Bool = false, trigger: String = "manual") {
        guard unlocked, sceneActive else {
            notice = "Unlock the app before connecting."
            return
        }
        guard !lifecycle.isStarting, !lifecycle.isLive else { return }
        retryTask?.cancel()
        retryTask = nil
        if !automatic { retryIndex = 0 }
        desiredActive = true
        notice = ""
        saveSession()
        if !lifecycle.timeline.isEmpty {
            previousAttempts.append(lifecycle.diagnostics)
            if previousAttempts.count > 5 { previousAttempts.removeFirst() }
        }
        let id = lifecycle.begin()
        lifecycle.note("connect trigger=\(trigger)")
        persistDiagnostics()
        guard !host.isEmpty, !username.isEmpty, !trustedHostKey.isEmpty,
            let portNumber = Int(port), (1...65535).contains(portNumber)
        else {
            fail(id, .init(stage: .preparation, code: "missingHostUserPortOrHostKey"))
            return
        }
        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try PhoneIdentityStore.loadOrCreate()
                publicKey = identity.publicKey
                lifecycle.note("app unlock valid; Ed25519 Keychain identity \(identity.publicKeyFingerprint)")
                activeIntent = try .selected(
                    useTmux: useTmux, diagnosticMode: diagnosticMode,
                    name: sessionName, create: createSession, reattaching: lifecycle.reachedConnected)
                let profile = SSHProfile(
                    host: host, port: portNumber, username: username,
                    trustedHostKey: trustedHostKey, intent: activeIntent, tmuxExecutable: tmuxPath)
                _ = try activeIntent.command(tmuxExecutable: tmuxPath)
                lifecycle.progress(id, .terminal)
                let pipe = TerminalInputPipe { [weak self] in
                    Task { @MainActor in self?.fail(id, .init(stage: .terminal, code: "inputBackpressure")) }
                }
                input = pipe
                let session = InMemoryTerminalSession(
                    write: { pipe.enqueue($0) },
                    resize: { [weak self] size in
                        Task { @MainActor in
                            guard let self, self.lifecycle.owns(id), self.isLive,
                                let connection = self.connection
                            else { return }
                            try? await connection.resize(columns: Int(size.columns), rows: Int(size.rows))
                        }
                    })
                let surface = TerminalViewState(terminalConfiguration: safeTerminalConfiguration())
                surface.makePlatformView = { PlainTextTerminalView(frame: .zero) }
                surface.configuration = .init(backend: .inMemory(session), fontSize: 14)
                surface.onClipboardConfirmationRequest = { $0.respond(allow: false) }
                surface.onTextSelectionRequest = { [weak self] request in
                    guard let self, self.lifecycle.owns(id), self.isLive, self.unlocked,
                        self.sceneActive
                    else { return }
                    self.selection = TerminalSelectionSnapshot(text: request.text, anchor: request.anchorRange)
                }
                candidate = surface
                // First connection may show the blank candidate. On reconnect the
                // old screen stays until remote acceptance and output are confirmed.
                if terminal == nil {
                    terminal = surface
                    presentedAttempt = id
                }
                let (events, continuation) = AsyncStream<ConnectionEvent>.makeStream()
                eventContinuation = continuation
                Task { [weak self] in
                    for await value in events { self?.event(id, value) }
                }
                let live = try await SSHConnection.connect(
                    profile: profile, identity: identity,
                    columns: max(1, Int(terminal?.surfaceSize?.columns ?? 80)),
                    rows: max(1, Int(terminal?.surfaceSize?.rows ?? 24)),
                    output: { [weak self] data in
                        session.receive(data)
                        session.waitForPendingOutput()
                        await self?.receivedOutput(id)
                    },
                    disconnected: {
                        continuation.yield(.closed)
                        continuation.finish()
                    },
                    event: { event in continuation.yield(event) })
                guard lifecycle.owns(id), unlocked, sceneActive, !Task.isCancelled else {
                    await live.close()
                    return
                }
                connection = live
                if activeIntent == .authenticationProbe {
                    notice = "SSH authentication passed. No session channel or PTY was requested."
                    desiredActive = false
                    stopTransport()
                    persistDiagnostics()
                    return
                }
                pipe.bind { bytes in try await live.send(bytes) }
                lifecycle.accepted(id)
                showConnectedIfReady(id)
                persistDiagnostics()
                // Accepted exec alone is not proof of a usable terminal.
                for _ in 0..<200 {
                    guard lifecycle.owns(id), lifecycle.firstFailure == nil else { return }
                    if lifecycle.isLive { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard lifecycle.owns(id) else { return }
                guard lifecycle.isLive else {
                    fail(id, .init(stage: .awaitingOutput, code: "noInteractiveOutputWithin10Seconds", retryable: true))
                    return
                }
                livenessTask = Task { [weak self] in
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(20))
                            try await live.checkLiveness()
                        }
                    } catch is CancellationError {} catch {
                        self?.fail(id, ConnectionFailure.capture(error, stage: .openingTransport))
                    }
                }
            } catch is CancellationError {
                // Explicit cancellation already changed ownership and state.
            } catch {
                guard lifecycle.owns(id) else { return }
                fail(id, ConnectionFailure.capture(error, stage: lifecycle.stage))
            }
        }
    }

    private func receivedOutput(_ id: UUID) {
        guard lifecycle.owns(id), lifecycle.isStarting else { return }
        if activeIntent == .diagnosticEcho {
            lifecycle.note("diagnostic command output received")
            persistDiagnostics()
            return
        }
        lifecycle.receivedOutput(id)
        showConnectedIfReady(id)
    }
    private func showConnectedIfReady(_ id: UUID) {
        guard lifecycle.owns(id), lifecycle.isLive else { return }
        if presentedAttempt != id {
            terminal = candidate
            presentedAttempt = id
        }
        candidate = nil
        retryIndex = 0
        if let size = terminal?.surfaceSize, let connection {
            Task { try? await connection.resize(columns: Int(size.columns), rows: Int(size.rows)) }
        }
        persistDiagnostics()
    }
    private func event(_ id: UUID, _ value: ConnectionEvent) {
        guard lifecycle.owns(id) else { return }
        switch value {
        case .closed: transportClosed(id)
        case .stage(let stage): lifecycle.progress(id, stage)
        case .note(let note): lifecycle.note(note)
        case .remoteExit(let code):
            lifecycle.note("remote exit status=\(code)")
            if activeIntent == .diagnosticEcho, code == 0 {
                notice = "SSH command test passed: exit status 0."
                desiredActive = false
                stopTransport()
                persistDiagnostics()
                return
            }
            let stage: ConnectionStage = useTmux ? .tmux : .shell
            fail(id, .init(stage: stage, code: "remoteExit=\(code)"))
        }
        persistDiagnostics()
    }
    private func transportClosed(_ id: UUID) {
        guard lifecycle.owns(id) else { return }
        let wasLive = lifecycle.isLive
        lifecycle.closed(id)
        persistDiagnostics()
        if wasLive {
            stopTransport(cancelAttempt: false)
            scheduleRetry()
        }
    }
    private func fail(_ id: UUID, _ failure: ConnectionFailure) {
        guard lifecycle.owns(id) else { return }
        let wasLive = lifecycle.isLive
        if !failure.retryable { desiredActive = false }
        if lifecycle.firstFailure != nil {
            lifecycle.fail(id, failure)
            persistDiagnostics()
            return
        }
        lifecycle.fail(id, failure)
        persistDiagnostics()
        stopTransport(cancelAttempt: false)
        if failure.retryable && (wasLive || lifecycle.reachedConnected) { scheduleRetry() }
    }
    private func scheduleRetry() {
        guard desiredActive, sceneActive, unlocked, retryTask == nil, retryIndex < retryDelays.count else { return }
        let index = retryIndex
        retryIndex += 1
        let id = lifecycle.attemptID
        lifecycle.retryScheduled(index)
        persistDiagnostics()
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(self?.retryDelays[index] ?? 0)) } catch { return }
            guard let self, self.lifecycle.owns(id), self.desiredActive, self.sceneActive, self.unlocked else {
                return
            }
            self.retryTask = nil
            self.connect(automatic: true, trigger: "retry timer")
        }
    }
    private func stopTransport(cancelAttempt: Bool = true) {
        terminal?.attachedPlatformView?.resignFirstResponder()
        eventContinuation?.finish()
        eventContinuation = nil
        input?.stop()
        input = nil
        connectTask?.cancel()
        connectTask = nil
        livenessTask?.cancel()
        livenessTask = nil
        retryTask?.cancel()
        retryTask = nil
        if let previous = connection { Task { await previous.close() } }
        connection = nil
        candidate = nil
        if cancelAttempt { lifecycle.stop() }
        pendingPasteAttempt = nil
    }
    func editConnection() {
        desiredActive = false
        stopTransport()
        terminal = nil
        presentedAttempt = nil
    }
    func disconnect() {
        desiredActive = false
        stopTransport()
        lifecycle.cancel()
        persistDiagnostics()
    }
    func phaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active: lifecycle.note("scene active")
        case .inactive: lifecycle.note("scene inactive")
        case .background: lifecycle.note("scene background; closing transport")
        @unknown default: lifecycle.note("scene unknown")
        }
        persistDiagnostics()
        if phase != .active { saveSession() }
        sceneActive = phase == .active
        if sceneActive {
            appLock.enterForeground(at: Date())
        } else {
            appLock.leaveForeground(at: Date())
        }
        scheduleBackgroundLock()
        terminal?.isSurfaceVisible = sceneActive
        if !sceneActive {
            selection = nil
            terminal?.attachedPlatformView?.resignFirstResponder()
        }
        if phase == .background {
            stopTransport()
            persistDiagnostics()
        } else if phase == .active {
            if !unlocked && !preparingKey { lock(reason: "foreground requires unlock") }
            if unlocked && desiredActive { connect(trigger: "foreground resume") }
        }
    }
    func pasteDraft() {
        guard isLive else { return }
        if draft.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }) {
            notice = "Remove control characters from the draft before pasting."
            return
        }
        pendingPasteAttempt = lifecycle.attemptID
        pasteWarning = true
    }
    func confirmPaste() {
        guard isLive, pendingPasteAttempt == lifecycle.attemptID, let terminal else {
            notice = "Connection changed. Inspect the terminal and request paste again."
            return
        }
        pendingPasteAttempt = nil
        terminal.onClipboardConfirmationRequest = { $0.respond(allow: $0.kind == .paste) }
        let accepted = terminal.paste(text: draft)
        terminal.onClipboardConfirmationRequest = { $0.respond(allow: false) }
        if !accepted { notice = "Paste was not accepted; draft retained." }
    }
}

@MainActor
struct RemoteTerminalScreen: View {
    var expanded = false
    @StateObject private var model = RemoteTerminalModel()
    @Environment(\.scenePhase) private var phase
    @State private var composing = false
    @State private var confirmingClearDraft = false
    @State private var showingSessionHelp = false

    var body: some View {
        VStack(spacing: 5) {
            Text(model.status).font(.callout).padding(8)
                .accessibilityIdentifier("remote.status")
                .accessibilityValue(model.accessibilityConnectionState)
            if !expanded || !model.isLive {
                if !model.notice.isEmpty { Text(model.notice).font(.caption) }
                Button("Copy Diagnostics") { model.copyDiagnostics() }
                if model.unlocked {
                    Button("Lock app") { model.lock() }
                    Button(model.useTmux ? "Saved session: \(model.sessionName) · Help" : "Shared session help") {
                        showingSessionHelp = true
                    }
                    .accessibilityIdentifier("remote.sessionHelp")
                }
                if model.unlocked && !model.isLive && model.terminal != nil {
                    Button("Connection settings") { model.editConnection() }
                }
                if !model.unlocked {
                    Button("Unlock MoshDeck") { Task { await model.unlock() } }.disabled(model.preparingKey)
                } else if model.busy {
                    ProgressView()
                    Button("Cancel connection") { model.disconnect() }
                } else if !model.isLive {
                    Button("Connect") { model.connect() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.preparingKey)
                }
            }
            if model.unlocked, let terminal = model.terminal {
                TerminalSurfaceView(context: terminal)
                    // The pinned wrapper assigns its UIKit delegate only in makeUIView.
                    // A new remote surface must not reuse the previous attempt's view.
                    .id(ObjectIdentifier(terminal))
                    .allowsHitTesting(model.isLive && phase == .active)
                HStack {
                    Button("Esc") { terminal.sendKey(.escape) }
                    Button("Ctrl-C") { terminal.sendKey(.c, modifiers: .ctrl) }
                    Button("Ctrl-B") { terminal.sendKey(.b, modifiers: .ctrl) }
                    Button("Compose") { composing = true }
                }.disabled(!model.isLive || phase != .active)
                if !expanded { Button("Disconnect") { model.disconnect() } }
            } else if model.unlocked {
                Form {
                    TextField("Tailnet hostname or IP", text: $model.host)
                    TextField("Mac username", text: $model.username)
                    TextField("Port", text: $model.port).keyboardType(.numberPad)
                    TextField("Verified OpenSSH host public key", text: $model.trustedHostKey)
                    Toggle("Use tmux", isOn: $model.useTmux)
                    if !model.useTmux {
                        Picker("SSH test", selection: $model.diagnosticMode) {
                            Text("Authentication only").tag("auth")
                            Text("Echo command (no PTY)").tag("echo")
                            Text("Clean interactive shell").tag("clean-shell")
                            Text("Normal login shell").tag("shell")
                        }
                    }
                    if model.useTmux {
                        TextField("Session", text: $model.sessionName)
                        TextField("tmux executable", text: $model.tmuxPath)
                        Toggle("Create if absent on first connect", isOn: $model.createSession)
                    }
                    Button("Unlock / show phone public key") { Task { await model.prepareKey() } }
                        .disabled(model.preparingKey)
                    if !model.publicKey.isEmpty {
                        Text(model.publicKey).font(.caption).textSelection(.enabled)
                        Button("Copy public key") { model.copyPublicKey() }
                        ShareLink("Share public key", item: model.publicKey)
                    }
                    Text(
                        "Profile and draft are saved in device-only Keychain storage. App unlock is separate from SSH authentication."
                    ).font(.caption)
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .overlay { if phase != .active { Color.black.ignoresSafeArea() } }
        .onChange(of: phase) { _, value in model.phaseChanged(value) }
        .onChange(of: model.unlocked) { _, unlocked in
            if !unlocked {
                composing = false
                showingSessionHelp = false
                model.selection = nil
            }
        }

        .sheet(isPresented: $showingSessionHelp) {
            NavigationStack {
                List {
                    Section("Attach from your Mac") {
                        Text("Open a new iTerm2 or Terminal tab on the configured Mac and run this command:")
                        if model.useTmux,
                            let command = try? SessionIntent.attach(name: model.sessionName).command(
                                tmuxExecutable: model.tmuxPath)
                        {
                            Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        } else {
                            Text(
                                "Enable Use tmux and enter an existing session name and valid executable path in connection settings first."
                            )
                        }
                        Text(
                            "Start your coding assistant inside tmux. An existing process in an ordinary terminal tab outside tmux cannot be adopted automatically."
                        )
                    }
                    Section("Switch sessions on iPhone") {
                        Text(
                            "Tap Ctrl-B once, then type lowercase s. Use the arrow keys to select a session in tmux's picker, then press Enter. Hide Keyboard gives the picker more room."
                        )
                        Text(
                            "Switching in tmux does not change this app's saved session. Reconnect returns to the saved target. To use another target after reconnect, disconnect and change Session in connection settings."
                        )
                    }
                    Section("Check shared control") {
                        Text(
                            "Both clients must select the same session and pane. At a shell prompt, type echo PHONE on the phone and echo MAC on the Mac. Each command and its output should appear on both screens. If a coding assistant is running, send a harmless prompt instead of a shell command."
                        )
                        Text(
                            "To detach one client, press Ctrl-B, release, then D. The other client and remote process stay attached/running. The exit command ends a shell; it is not a detach command."
                        )
                    }
                }
                .navigationTitle("Shared sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { showingSessionHelp = false } }
                .overlay {
                    if !model.unlocked || phase != .active { Color.black.ignoresSafeArea() }
                }
            }
        }
        .sheet(item: $model.selection) { snapshot in
            NavigationStack {
                TerminalSelectionText(snapshot: snapshot)
                    .navigationTitle("Select terminal text")
                    .toolbar { Button("Done") { model.selection = nil } }
                    .overlay {
                        if !model.unlocked || phase != .active { Color.black.ignoresSafeArea() }
                    }
            }
        }
        .sheet(isPresented: $composing, onDismiss: { model.saveSession() }) {
            NavigationStack {
                VStack {
                    Text("\(model.host) · \(model.useTmux ? model.sessionName : "shell")").font(.caption)
                    TextEditor(text: $model.draft).accessibilityLabel("Prompt draft")
                    Button("Paste without added Enter") { model.pasteDraft() }.disabled(!model.isLive)
                    Button("Enter key") { model.terminal?.sendKey(.enter) }.disabled(!model.isLive)
                }.padding().navigationTitle("Compose")
                    .overlay {
                        if !model.unlocked || phase != .active { Color.black.ignoresSafeArea() }
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Clear draft", role: .destructive) { confirmingClearDraft = true }
                                .disabled(model.draft.isEmpty)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { composing = false }
                        }
                    }
                    .alert("Clear this draft?", isPresented: $confirmingClearDraft) {
                        Button("Clear draft", role: .destructive) {
                            model.draft = ""
                            model.saveSession()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes the saved draft from this device.")
                    }
                    .confirmationDialog(
                        "Pasted newlines may execute in a shell. Inspect the host and foreground program before pasting.",
                        isPresented: $model.pasteWarning, titleVisibility: .visible
                    ) {
                        Button("Paste inspected text") { model.confirmPaste() }
                    }
            }
        }
    }
}

// A user-requested viewport snapshot: memory-only and discarded on dismissal or inactivity.
struct TerminalSelectionSnapshot: Identifiable {
    let id = UUID()
    let text: String
    let anchor: NSRange?
}

private struct TerminalSelectionText: UIViewRepresentable {
    let snapshot: TerminalSelectionSnapshot

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = UIFontMetrics.default.scaledFont(for: .monospacedSystemFont(ofSize: 14, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityLabel = "Terminal text for selection and copy"
        view.text = snapshot.text
        let length = (snapshot.text as NSString).length
        if let anchor = snapshot.anchor, anchor.location >= 0, anchor.length >= 0,
            anchor.location <= length,
            anchor.length <= length - anchor.location
        {
            view.selectedRange = anchor
        } else {
            view.selectedRange = NSRange(location: 0, length: length)
        }
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}
}
