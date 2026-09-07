import Foundation

public enum ConnectionStage: String, Sendable, CaseIterable {
    case preparation, terminal, openingTransport, negotiatingSSH, hostVerification
    case authentication, sessionChannel, pty, shell, tmux, awaitingOutput
}

public struct ConnectionFailure: Error, Sendable, Equatable {
    public let stage: ConnectionStage
    public let code: String
    public let retryable: Bool
    public init(stage: ConnectionStage, code: String, retryable: Bool = false) {
        self.stage = stage
        self.code = code
        self.retryable = retryable
    }
}

public enum ConnectionEvent: Sendable {
    case stage(ConnectionStage)
    case note(String)
    case remoteExit(Int)
    case closed
}

public enum ConnectionState: Sendable, Equatable {
    case idle
    case starting(ConnectionStage)
    case connected
    case reconnecting(Int)
    case disconnected, cancelled
    case failed(ConnectionFailure)
}

/// Deterministic attempt ownership. Cleanup cannot erase the first fatal cause.
public struct ConnectionLifecycle: Sendable {
    public private(set) var attemptID = UUID()
    public private(set) var state: ConnectionState = .idle
    public private(set) var stage: ConnectionStage = .preparation
    public private(set) var firstFailure: ConnectionFailure?
    public private(set) var timeline: [String] = []
    public private(set) var reachedConnected = false
    private var acceptsEvents = false
    public private(set) var remoteAccepted = false
    public private(set) var outputReceived = false
    public init() {}
    public var isLive: Bool { state == .connected }
    public var isStarting: Bool {
        if case .starting = state { return true }
        return false
    }
    public func owns(_ id: UUID) -> Bool { id == attemptID && acceptsEvents }
    public mutating func begin() -> UUID {
        acceptsEvents = true
        attemptID = UUID()
        stage = .preparation
        firstFailure = nil
        remoteAccepted = false
        outputReceived = false
        state = .starting(.preparation)
        timeline = []
        note("attempt started")
        return attemptID
    }
    public mutating func note(_ value: String) {
        // Callers pass fixed diagnostic vocabulary and numeric codes, never payloads.
        if timeline.count == 100 { timeline.removeFirst() }
        timeline.append("\(Date().timeIntervalSince1970): \(value)")
    }
    public mutating func progress(_ id: UUID, _ value: ConnectionStage) {
        guard owns(id), isStarting, firstFailure == nil else { return }
        stage = value
        state = .starting(value)
        note("stage=\(value.rawValue)")
    }
    public mutating func accepted(_ id: UUID) {
        guard owns(id), isStarting else { return }
        remoteAccepted = true
        readyIfPossible()
    }
    public mutating func receivedOutput(_ id: UUID) {
        guard owns(id), isStarting else { return }
        outputReceived = true
        readyIfPossible()
    }
    private mutating func readyIfPossible() {
        if remoteAccepted && outputReceived {
            state = .connected
            reachedConnected = true
            note("interactive output received; connected")
        }
    }
    public mutating func fail(_ id: UUID, _ failure: ConnectionFailure) {
        guard owns(id), state != .cancelled, state != .idle else { return }
        guard firstFailure == nil else {
            note("secondary failure: \(failure.code)")
            return
        }
        firstFailure = failure
        state = .failed(failure)
        note("FAIL stage=\(failure.stage.rawValue) code=\(failure.code)")
    }
    public mutating func closed(_ id: UUID) {
        guard owns(id) else { return }
        note("channel closed")
        if firstFailure != nil || state == .cancelled || state == .idle { return }
        if isLive { state = .reconnecting(0) }
        // Startup close is context only: the transport's thrown first failure wins.
    }
    public mutating func retryScheduled(_ index: Int) { state = .reconnecting(index) }
    public mutating func cancel() {
        note("cancelled by owner")
        state = .cancelled
        acceptsEvents = false
    }
    public mutating func stop() {
        note("disconnected")
        if firstFailure == nil { state = .disconnected }
        acceptsEvents = false
    }
    public var diagnostics: String {
        "MoshDeck Connection Diagnostics\nattempt: \(attemptID)\nstate: \(state)\nstage: \(stage.rawValue)\ntransport: SSH\n"
            + timeline.joined(separator: "\n")
    }
}

public enum AppLockState: Sendable, Equatable {
    case locked, unlocking
    case unlocked(until: Date)
    case unlockFailed
}

public struct AppLockPolicy: Sendable {
    public private(set) var state: AppLockState = .locked
    public let grace: TimeInterval
    public init(grace: TimeInterval = 300) { self.grace = grace }
    public func permitsAccess(at now: Date) -> Bool {
        if case .unlocked(let until) = state { return now < until }
        return false
    }
    public mutating func beginUnlock() { state = .unlocking }
    public mutating func unlocked(at now: Date) { state = .unlocked(until: now.addingTimeInterval(grace)) }
    public mutating func failed() { state = .unlockFailed }
    public mutating func lock() { state = .locked }
}

extension ConnectionStage {
    public var title: String {
        switch self {
        case .preparation: "Preparing connection"
        case .terminal: "Preparing terminal"
        case .openingTransport: "Opening network connection"
        case .negotiatingSSH: "Negotiating SSH"
        case .hostVerification: "Verifying Mac identity"
        case .authentication: "Authenticating SSH key"
        case .sessionChannel: "Opening terminal channel"
        case .pty: "Requesting terminal"
        case .shell: "Starting shell"
        case .tmux: "Attaching tmux"
        case .awaitingOutput: "Waiting for terminal output"
        }
    }
}

extension ConnectionFailure {
    public var message: String {
        if code == "missingHostUserPortOrHostKey" { return "Enter host, username, port and verified host public key." }
        if code == "hostKeyMismatch" {
            return "The Mac's host key does not match. Verify its identity before retrying."
        }
        if code == "authenticationRejected" {
            return "The Mac rejected the SSH key. Check the matching public key in authorized_keys."
        }
        if stage == .pty && code == "requestRejected" {
            return "SSH authenticated, but the Mac rejected terminal allocation."
        }
        if code.hasPrefix("remoteExit=") {
            return "The remote shell or tmux command exited. Check the selected session and startup command."
        }
        if stage == .awaitingOutput {
            return "The remote command was accepted, but no terminal output arrived before the deadline."
        }
        return "\(stage.title) failed (\(code)). Copy Diagnostics for the full attempt timeline."
    }
}
