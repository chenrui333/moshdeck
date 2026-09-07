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
        case .failed(let failure): return "Failed at \(failure.stage.rawValue): \(failure.message)"
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
        if !sceneActive { terminal?.attachedPlatformView?.resignFirstResponder() }
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

    var body: some View {
        VStack(spacing: 5) {
            Text(model.status).font(.callout).padding(8)
                .accessibilityIdentifier("remote.status")
            if !expanded || !model.isLive {
                if !model.notice.isEmpty { Text(model.notice).font(.caption) }
                Button("Copy Diagnostics") { model.copyDiagnostics() }
                if model.unlocked { Button("Lock app") { model.lock() } }
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
            if !unlocked { composing = false }
        }

        .sheet(isPresented: $composing) {
            NavigationStack {
                VStack {
                    Text("\(model.host) · \(model.useTmux ? model.sessionName : "shell")").font(.caption)
                    TextEditor(text: $model.draft).accessibilityLabel("Prompt draft")
                    Button("Paste without added Enter") { model.pasteDraft() }.disabled(!model.isLive)
                    Button("Enter key") { model.terminal?.sendKey(.enter) }.disabled(!model.isLive)
                }.padding().navigationTitle("Compose")
                    .overlay { if !model.unlocked { Color.black.ignoresSafeArea() } }
                    .toolbar { Button("Done") { composing = false } }
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
