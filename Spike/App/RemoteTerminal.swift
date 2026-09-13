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
    @Published private(set) var listedSessions: [TmuxSessionSummary] = []
    @Published private(set) var listingSessions = false
    @Published private(set) var sessionListError: String?
    @Published private(set) var observedSession: String?
    @Published private(set) var switchingSession = false
    @Published private(set) var swipePreview: SessionSwipePreview?
    var sessionNavigationPresented = false
    private var switchTask: Task<Void, Never>?
    private var sessionListRequest = UUID()
    private var listedAttempt: UUID?
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
    var canSendInput: Bool { isLive && !switchingSession && swipePreview == nil }
    var canSwipeSessions: Bool {
        isLive && useTmux && !switchingSession && !listingSessions && !sessionNavigationPresented
            && selection == nil && listedAttempt == lifecycle.attemptID && observedSession != nil
    }
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
                surface.makePlatformView = { [weak self] in
                    let view = PlainTextTerminalView(frame: .zero)
                    view.acceptsTerminalInput = { [weak self] in self?.canSendInput == true }
                    view.sessionSwipe?.enabled = { [weak self] in self?.canSwipeSessions == true }
                    view.sessionSwipe?.update = { [weak self] phase, delta, velocity, width in
                        self?.updateSessionSwipe(phase, delta: delta, velocity: velocity, width: width)
                    }
                    return view
                }
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
                if useTmux { await listSessions() }
                livenessTask = Task { [weak self] in
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(20))
                            try await live.checkLiveness()
                            if let self, self.canSwipeSessions, self.swipePreview == nil { await self.listSessions() }
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
        switchTask?.cancel()
        switchTask = nil
        switchingSession = false
        swipePreview = nil
        observedSession = nil
        listedAttempt = nil
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
    func listSessions() async {
        let request = UUID()
        sessionListRequest = request
        listedSessions = []
        listedAttempt = nil
        sessionListError = nil
        guard isLive, useTmux, let connection else {
            sessionListError = "Connect to a tmux session before refreshing this list."
            listingSessions = false
            return
        }
        let attempt = lifecycle.attemptID
        listingSessions = true
        defer { if sessionListRequest == request { listingSessions = false } }
        do {
            let snapshot = try await connection.tmuxSnapshot(executable: tmuxPath)
            guard sessionListRequest == request, lifecycle.owns(attempt), isLive, !Task.isCancelled else { return }
            listedSessions = snapshot.sessions
            observedSession = snapshot.currentSession
            listedAttempt = attempt
        } catch is CancellationError {
            // Closing the panel cancels only its auxiliary SSH channel.
        } catch {
            guard sessionListRequest == request, lifecycle.owns(attempt), isLive, !Task.isCancelled else { return }
            sessionListError =
                "Could not identify this phone’s tmux client. Refresh, or use the terminal picker (Ctrl-B, s)."
        }
    }

    func attachListedSession(_ session: TmuxSessionSummary) -> Bool {
        guard isLive, !switchingSession, listedAttempt == lifecycle.attemptID,
            listedSessions.contains(session), session.canAttach, let source = observedSession,
            let connection
        else { return false }
        if source == session.name { return true }
        let attempt = lifecycle.attemptID
        switchingSession = true
        input?.setAcceptingInput(false)
        pendingPasteAttempt = nil
        pasteWarning = false
        notice = ""
        terminal?.attachedPlatformView?.resetStickyModifiers()
        switchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if lifecycle.owns(attempt) {
                    switchingSession = false
                    switchTask = nil
                    input?.setAcceptingInput(isLive)
                }
            }
            do {
                // Drain already accepted input to its original destination before
                // switching; new input is disabled rather than deferred.
                await input?.waitForDrain()
                guard lifecycle.owns(attempt), isLive, !Task.isCancelled else { return }
                try await connection.switchTmuxSession(to: session.name, from: source, executable: tmuxPath)
                guard lifecycle.owns(attempt), isLive, !Task.isCancelled else { return }
                sessionName = session.name
                observedSession = session.name
                activeIntent = .attach(name: session.name)
                createSession = false
                saveSession()
                lifecycle.note("native session switch confirmed")
                persistDiagnostics()
            } catch is CancellationError {
                // A late completion must never change a newer connection's target.
            } catch {
                guard lifecycle.owns(attempt), isLive else { return }
                notice =
                    "Session switch was not confirmed. Reconnect target unchanged. Refresh the session list and try again."
                lifecycle.note("native session switch unconfirmed")
                persistDiagnostics()
            }
            if lifecycle.owns(attempt), isLive, !Task.isCancelled { await listSessions() }
        }
        return true
    }

    func updateSessionSwipe(_ phase: TerminalSessionSwipe.Phase, delta: CGPoint, velocity: CGFloat, width: CGFloat) {
        guard canSwipeSessions else {
            swipePreview = nil
            input?.setAcceptingInput(isLive && !switchingSession)
            return
        }
        switch phase {
        case .began:
            input?.setAcceptingInput(false)
            guard let source = observedSession else { return }
            swipePreview = SessionSwipePreview(
                source: source, target: SessionSwipe.target(in: listedSessions, current: source, x: delta.x),
                next: delta.x < 0, progress: 0)
        case .changed:
            if var preview = swipePreview {
                let sameDirection = (delta.x < 0) == preview.next
                preview.progress = sameDirection ? min(1, abs(delta.x) / SessionSwipe.threshold(width: width)) : 0
                swipePreview = preview
            }
        case .ended:
            input?.setAcceptingInput(true)
            let preview = swipePreview
            swipePreview = nil
            guard let preview, let target = preview.target, observedSession == preview.source,
                (delta.x < 0) == preview.next,
                SessionSwipe.commits(x: delta.x, y: delta.y, velocityX: velocity, width: width)
            else { return }
            _ = attachListedSession(target)
        case .cancelled:
            swipePreview = nil
            input?.setAcceptingInput(true)
        }
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
        guard canSendInput else { return }
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
        guard canSendInput, pendingPasteAttempt == lifecycle.attemptID, let terminal else {
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
    @StateObject private var model = RemoteTerminalModel()
    @Environment(\.scenePhase) private var phase
    @State private var composing = false
    @State private var confirmingClearDraft = false
    @State private var showingSessionHelp = false
    @State private var showingDetails = false
    @State private var showingSessions = false
    @State private var sessionRefresh = UUID()

    var body: some View {
        VStack(spacing: 0) {
            contextBar
            if !model.unlocked {
                Spacer()
                Button("Unlock MoshDeck") { Task { await model.unlock() } }
                    .buttonStyle(.borderedProminent).disabled(model.preparingKey)
                if !model.notice.isEmpty { Text(model.notice).font(.caption).padding() }
                Spacer()
            } else if !model.isLive {
                connectionBanner
            }
            if model.isLive && model.notice.hasPrefix("Session switch") {
                Text(model.notice).font(.caption).padding(8)
                    .accessibilityIdentifier("session.switch.error")
            }
            if model.unlocked, let terminal = model.terminal {
                TerminalSurfaceView(context: terminal)
                    // The pinned wrapper assigns its UIKit delegate only in makeUIView.
                    // A new remote surface must not reuse the previous attempt's view.
                    .id(ObjectIdentifier(terminal))
                    .allowsHitTesting(model.isLive && phase == .active)
                    .overlay(alignment: model.swipePreview?.next == true ? .trailing : .leading) {
                        if let preview = model.swipePreview { SessionSwipePreviewView(preview: preview) }
                    }
            } else if model.unlocked {
                Form {
                    TextField("Tailnet hostname or IP", text: $model.host)
                    TextField("Mac username", text: $model.username)
                    TextField("Port", text: $model.port).keyboardType(.numberPad)
                    TextField("Verified OpenSSH host public key", text: $model.trustedHostKey)
                    Toggle("Use tmux", isOn: $model.useTmux)
                    if !model.useTmux {
                        Picker("Shell startup", selection: $model.diagnosticMode) {
                            #if DEBUG
                                Text("Authentication only").tag("auth")
                                Text("Echo command (no PTY)").tag("echo")
                            #endif
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
        .accessibilityHidden(showingSessions)
        .allowsHitTesting(!showingSessions)
        .overlay(alignment: .leading) {
            if showingSessions && model.unlocked && phase == .active {
                TmuxSessionsPanel(
                    sessions: model.listedSessions, loading: model.listingSessions,
                    error: model.sessionListError, reconnectTarget: model.sessionName,
                    canSelect: model.isLive && !model.listingSessions && !model.switchingSession,
                    select: { if model.attachListedSession($0) { showingSessions = false } },
                    refresh: { sessionRefresh = UUID() },
                    close: { showingSessions = false },
                    terminalPicker: {
                        showingSessions = false
                        sendTmuxPrefix(switchSession: true)
                    }
                )
                .task(id: sessionRefresh) { await model.listSessions() }
            }
        }
        .overlay { if phase != .active { Color.black.ignoresSafeArea() } }
        .onChange(of: phase) { _, value in
            if value != .active { model.updateSessionSwipe(.cancelled, delta: .zero, velocity: 0, width: 0) }
            if value != .active { showingSessions = false }
            model.phaseChanged(value)
        }
        .onChange(of: composing || showingSessions || showingDetails || showingSessionHelp) { _, presented in
            model.sessionNavigationPresented = presented
        }
        .onChange(of: model.lifecycle.attemptID) { _, _ in showingSessions = false }
        .onChange(of: model.unlocked) { _, unlocked in
            if !unlocked {
                composing = false
                showingSessionHelp = false
                showingDetails = false
                showingSessions = false
                model.selection = nil
            }
        }

        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                List {
                    Section("Connection") {
                        LabeledContent("Host", value: model.host)
                        LabeledContent("Username", value: model.username)
                        LabeledContent("Port", value: model.port)
                        if model.useTmux { LabeledContent("Reconnect target", value: model.sessionName) }
                        Text(model.status)
                        if !model.notice.isEmpty { Text(model.notice) }
                    }
                    Section("Diagnostics") {
                        Text(
                            "Copies connection stages and safe error categories. Terminal contents and credentials are excluded."
                        )
                        Button("Copy Diagnostics") { model.copyDiagnostics() }
                    }
                }
                .navigationTitle("Connection details").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { showingDetails = false } }
                .overlay { if !model.unlocked || phase != .active { Color.black.ignoresSafeArea() } }
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
        .sheet(
            isPresented: $composing, onDismiss: { model.saveSession() },
            content: {
                NavigationStack {
                    VStack {
                        Text("\(model.host) · \(model.useTmux ? "Reconnect target: " + model.sessionName : "shell")")
                            .font(
                                .caption)
                        TextEditor(text: $model.draft).accessibilityLabel("Prompt draft")
                        if !model.notice.isEmpty { Text(model.notice).font(.caption).lineLimit(2) }
                        Button("Paste without added Enter") { model.pasteDraft() }.disabled(!model.canSendInput)
                        Button("Enter key") { model.terminal?.sendKey(.enter) }.disabled(!model.canSendInput)
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
            })
    }

    private var contextBar: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.unlocked && !model.host.isEmpty ? model.host : "MoshDeck")
                    .font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(compactStatus).font(.caption)
                    .accessibilityIdentifier("remote.status")
                    .accessibilityValue(model.accessibilityConnectionState)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.unlocked {
                if let terminal = model.terminal {
                    TerminalKeyboardButton(terminal: terminal, enabled: model.canSendInput)
                }
                Button {
                    dismissKeyboard()
                    showingSessions = true
                } label: {
                    HStack(spacing: 3) {
                        Text("Sessions").font(.callout)
                        Image(systemName: "chevron.down").font(.caption2)
                    }.frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Switch Session")
                .disabled(!model.isLive || !model.useTmux || model.switchingSession)
                Button {
                    dismissKeyboard()
                    composing = true
                } label: {
                    Image(systemName: "square.and.pencil").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Compose")
                Menu {
                    Button("Send Ctrl-B") { sendTmuxPrefix(switchSession: false) }
                        .disabled(!model.canSendInput)
                    Button("How to Attach from Mac") { showSessionHelp() }
                        .accessibilityIdentifier("remote.sessionHelp")
                    if model.useTmux { Text("Reconnect target: \(model.sessionName)") }
                    Button("Connection Details") {
                        dismissKeyboard()
                        showingDetails = true
                    }
                    Button("Profile / Settings") { model.editConnection() }
                        .disabled(model.isLive || model.busy)
                    Button("Copy Diagnostics") { model.copyDiagnostics() }
                    Button("Disconnect") { model.disconnect() }
                    Button("Lock app") { model.lock() }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Terminal actions")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 2).background(.bar)
    }

    private var compactStatus: String {
        if !model.unlocked { return model.status }
        if model.switchingSession { return "Switching session…" }
        switch model.lifecycle.state {
        case .failed: return "Disconnected"
        case .disconnected: return "Disconnected"
        default: return model.status
        }
    }

    private var connectionBanner: some View {
        VStack(spacing: 4) {
            if case .failed(let failure) = model.lifecycle.state {
                Text(failure.title).font(.callout.weight(.semibold))
                Text(failure.message).font(.caption).lineLimit(3)
            }
            if !model.notice.isEmpty { Text(model.notice).font(.caption).lineLimit(2) }
            HStack {
                if model.busy {
                    ProgressView()
                    Button("Cancel connection") { model.disconnect() }
                } else {
                    Button(model.terminal == nil ? "Connect" : "Reconnect") { model.connect() }
                        .buttonStyle(.borderedProminent).disabled(model.preparingKey)
                }
                Button("Details") {
                    dismissKeyboard()
                    showingDetails = true
                }
            }
        }.padding(8)
    }

    private func dismissKeyboard() {
        model.terminal?.attachedPlatformView?.resignFirstResponder()
    }

    private func showSessionHelp() {
        dismissKeyboard()
        showingSessionHelp = true
    }

    private func sendTmuxPrefix(switchSession: Bool) {
        // Synchronous deliberate key events. No timers, shell commands or input queue.
        guard model.canSendInput, phase == .active, let view = model.terminal?.attachedPlatformView else { return }
        view.resetStickyModifiers()
        guard view.sendKey(.b, modifiers: .ctrl) else { return }
        if switchSession { view.sendKey(.s) }
        model.terminal?.requestFocus()
    }

}

@MainActor
private struct TerminalKeyboardButton: View {
    @ObservedObject var terminal: TerminalViewState
    let enabled: Bool

    var body: some View {
        if !terminal.isFocused {
            Button {
                terminal.requestFocus()
            } label: {
                Image(systemName: "keyboard").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Show Keyboard").disabled(!enabled)
        }
    }
}

// A user-requested viewport snapshot: memory-only and discarded on dismissal or inactivity.
struct TerminalSelectionSnapshot: Identifiable {
    let id = UUID()
    let text: String
    let anchor: NSRange?
}

struct TerminalSelectionText: UIViewRepresentable {
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
