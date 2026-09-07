import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public struct SSHIdentity: Sendable {
    fileprivate let key: NIOSSHPrivateKey
    /// Store this only in Keychain outside disposable test fixtures.
    public let privateKeyRepresentation: Data
    public var publicKey: String { String(openSSHPublicKey: key.publicKey) }
    public var publicKeyFingerprint: String {
        let parts = publicKey.split(separator: " ")
        guard parts.count >= 2, let data = Data(base64Encoded: String(parts[1])) else { return "unavailable" }
        return "SHA256:" + Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    public init(privateKeyRepresentation: Data? = nil) throws {
        let signingKey =
            try privateKeyRepresentation.map { try Curve25519.Signing.PrivateKey(rawRepresentation: $0) }
            ?? Curve25519.Signing.PrivateKey()
        self.privateKeyRepresentation = signingKey.rawRepresentation
        key = NIOSSHPrivateKey(ed25519Key: signingKey)
    }
}

public struct SSHProfile: Sendable {
    public var host: String
    public var port: Int
    public var username: String
    public var trustedHostKey: String
    public var intent: SessionIntent
    public var tmuxExecutable: String

    public init(
        host: String, port: Int = 22, username: String, trustedHostKey: String,
        intent: SessionIntent = .shell, tmuxExecutable: String = "tmux"
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.trustedHostKey = trustedHostKey
        self.intent = intent
        self.tmuxExecutable = tmuxExecutable
    }
}

public enum SSHConnectionError: Error, Sendable, Equatable {
    case hostKeyMismatch, authenticationRejected, requestRejected, invalidChannel
    case timedOut, disconnected, outputLimitExceeded, inputBackpressure, invalidSize
}

/// One connection, one PTY. UI lifecycle and renderer ownership stay outside.
public actor SSHConnection {
    private let parent: Channel
    private let terminal: Channel
    private let inputAllowed: Bool
    private var closed = false
    private var pendingInputBytes = 0

    private init(parent: Channel, terminal: Channel, inputAllowed: Bool = true) {
        self.inputAllowed = inputAllowed
        self.parent = parent
        self.terminal = terminal
    }

    public static func connect(
        profile: SSHProfile, identity: SSHIdentity, columns: Int, rows: Int,
        output: @escaping @Sendable (Data) async -> Void,
        disconnected: @escaping @Sendable () -> Void = {},
        event: @escaping @Sendable (ConnectionEvent) -> Void = { _ in }
    ) async throws -> SSHConnection {
        let cancellation = ConnectionCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await connectAttempt(
                profile: profile, identity: identity, columns: columns, rows: rows,
                output: output, disconnected: disconnected, event: event, cancellation: cancellation)
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func connectAttempt(
        profile: SSHProfile, identity: SSHIdentity, columns: Int, rows: Int,
        output: @escaping @Sendable (Data) async -> Void,
        disconnected: @escaping @Sendable () -> Void,
        event: @escaping @Sendable (ConnectionEvent) -> Void,
        cancellation: ConnectionCancellation
    ) async throws -> SSHConnection {
        guard (1...1000).contains(columns), (1...1000).contains(rows) else {
            throw SSHConnectionError.invalidSize
        }
        let expectedKey = try NIOSSHPublicKey(openSSHPublicKey: profile.trustedHostKey)
        let command = try profile.intent.command(tmuxExecutable: profile.tmuxExecutable)
        let loop = MultiThreadedEventLoopGroup.singleton.next()
        let ready = loop.makePromise(of: Void.self)
        let startup = StartupCompletion(ready, authenticationOnly: profile.intent == .authenticationProbe, event: event)
        event(.stage(.openingTransport))
        let parent: Channel
        do {
            parent = try await ClientBootstrap(group: loop)
                .connectTimeout(.seconds(10))
                .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
                .channelInitializer { channel in
                    cancellation.register(channel)
                    return channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandlers(
                            NIOSSHHandler(
                                role: .client(
                                    .init(
                                        userAuthDelegate: KeyAuthentication(
                                            username: profile.username, key: identity.key, startup: startup),
                                        serverAuthDelegate: PinnedHostKey(expected: expectedKey, startup: startup)
                                    )), allocator: channel.allocator, inboundChildChannelInitializer: nil),
                            ConnectionErrors(startup: startup)
                        )
                    }
                }.connect(host: profile.host, port: profile.port).get()
        } catch {
            let failure = ConnectionFailure.capture(error, stage: .openingTransport)
            loop.execute { startup.finish(.failure(failure)) }
            _ = try? await ready.futureResult.get()
            throw failure
        }
        // NIOSSHHandler consumes channelInactive instead of forwarding it.
        // closeFuture is the authoritative parent-channel lifetime signal.
        parent.closeFuture.whenComplete { _ in
            startup.finish(.failure(SSHConnectionError.disconnected))
            disconnected()
        }
        let timer = loop.scheduleTask(in: .seconds(15)) {
            startup.finish(.failure(SSHConnectionError.timedOut))
            parent.close(promise: nil)
        }
        defer { timer.cancel() }
        do {
            if profile.intent == .authenticationProbe {
                try await ready.futureResult.get()
                try Task.checkCancellation()
                return SSHConnection(parent: parent, terminal: parent, inputAllowed: false)
            }
            let childPromise = loop.makePromise(of: Channel.self)
            parent.eventLoop.execute {
                do {
                    let handler = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                    handler.createChannel(childPromise) { channel, kind in
                        guard kind == .session else {
                            return channel.eventLoop.makeFailedFuture(SSHConnectionError.invalidChannel)
                        }
                        return channel.setOption(ChannelOptions.autoRead, value: false).flatMap {
                            channel.eventLoop.makeCompletedFuture {
                                try channel.pipeline.syncOperations.addHandler(
                                    PTYHandler(
                                        command: command, columns: columns, rows: rows,
                                        startup: startup, output: output,
                                        remoteStage: (profile.intent == .shell || profile.intent == .diagnosticEcho
                                            || profile.intent == .diagnosticShell) ? .shell : .tmux,
                                        requiresPTY: profile.intent != .diagnosticEcho
                                    ))
                            }
                        }
                    }
                } catch { childPromise.fail(error) }
            }
            let terminal = try await childPromise.futureResult.get()
            terminal.closeFuture.whenComplete { _ in parent.close(promise: nil) }
            try await ready.futureResult.get()
            try Task.checkCancellation()
            return SSHConnection(parent: parent, terminal: terminal)
        } catch {
            try? await parent.close().get()
            // Channel creation can fail as a consequence of the earlier auth
            // failure. Preserve that first cause for actionable trust UI.
            try await ready.futureResult.get()
            throw error
        }
    }

    /// A completed write is not acknowledgement that a shell executed the input.
    /// The caller must never retry an ambiguous write automatically.
    public func send(_ data: Data) async throws {
        guard inputAllowed else { throw SSHConnectionError.invalidChannel }
        guard !closed, terminal.isActive else { throw SSHConnectionError.disconnected }
        guard data.count <= 64 * 1024, pendingInputBytes + data.count <= 128 * 1024,
            terminal.isWritable
        else { throw SSHConnectionError.inputBackpressure }
        pendingInputBytes += data.count
        defer { pendingInputBytes -= data.count }
        let buffer = terminal.allocator.buffer(bytes: data)
        try await terminal.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer))).get()
    }

    public func resize(columns: Int, rows: Int) async throws {
        guard inputAllowed else { throw SSHConnectionError.invalidChannel }
        guard !closed else { throw SSHConnectionError.disconnected }
        guard (1...1000).contains(columns), (1...1000).contains(rows) else {
            throw SSHConnectionError.invalidSize
        }
        try await terminal.triggerUserOutboundEvent(
            SSHChannelRequestEvent.WindowChangeRequest(
                terminalCharacterWidth: columns, terminalRowHeight: rows,
                terminalPixelWidth: 0, terminalPixelHeight: 0
            )
        ).get()
    }

    /// A session-channel open/close requires an authenticated SSH response but
    /// starts no process and writes nothing to the terminal. The caller schedules
    /// this only while foregrounded. Failure closes the suspect connection.
    public func checkLiveness() async throws {
        guard !closed, parent.isActive else { throw SSHConnectionError.disconnected }
        let channel = parent
        let promise = channel.eventLoop.makePromise(of: Channel.self)
        let timer = channel.eventLoop.scheduleTask(in: .seconds(5)) {
            channel.close(promise: nil)
        }
        defer { timer.cancel() }
        channel.eventLoop.execute {
            do {
                let handler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                handler.createChannel(promise) { child, kind in
                    guard kind == .session else {
                        return child.eventLoop.makeFailedFuture(SSHConnectionError.invalidChannel)
                    }
                    return child.eventLoop.makeSucceededVoidFuture()
                }
            } catch { promise.fail(error) }
        }
        do {
            let probe = try await promise.futureResult.get()
            try await probe.close().get()
        } catch {
            await close()
            throw error
        }
    }

    public func close() async {
        guard !closed else { return }
        closed = true
        try? await parent.close().get()
    }
}

// All mutable handler state is confined to the connection's event loop.
// Sendable is needed only for callbacks enqueued to that same loop.
private final class StartupCompletion: @unchecked Sendable {
    private var promise: EventLoopPromise<Void>?
    private(set) var stage: ConnectionStage = .negotiatingSSH
    let event: @Sendable (ConnectionEvent) -> Void
    let authenticationOnly: Bool
    init(
        _ promise: EventLoopPromise<Void>, authenticationOnly: Bool,
        event: @escaping @Sendable (ConnectionEvent) -> Void
    ) {
        self.promise = promise
        self.authenticationOnly = authenticationOnly
        self.event = event
    }
    func progress(_ stage: ConnectionStage) {
        self.stage = stage
        event(.stage(stage))
    }
    func finish(_ result: Result<Void, Error>) {
        guard let promise else { return }
        promise.futureResult.eventLoop.preconditionInEventLoop()
        self.promise = nil
        switch result {
        case .success: promise.succeed(())
        case .failure(let error): promise.fail(ConnectionFailure.capture(error, stage: stage))
        }
    }
}

private final class PinnedHostKey: NIOSSHClientServerAuthenticationDelegate {
    let expected: NIOSSHPublicKey
    let startup: StartupCompletion
    init(expected: NIOSSHPublicKey, startup: StartupCompletion) {
        self.expected = expected
        self.startup = startup
    }
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        startup.progress(.hostVerification)
        if hostKey == expected {
            startup.event(.note("host key matched"))
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(SSHConnectionError.hostKeyMismatch)
        }
    }
}

private final class KeyAuthentication: NIOSSHClientUserAuthenticationDelegate {
    let username: String
    let key: NIOSSHPrivateKey
    private var offered = false
    let startup: StartupCompletion
    init(username: String, key: NIOSSHPrivateKey, startup: StartupCompletion) {
        self.startup = startup
        self.username = username
        self.key = key
    }
    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        startup.progress(.authentication)
        guard !offered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(SSHConnectionError.authenticationRejected)
            return
        }
        offered = true
        nextChallengePromise.succeed(
            .init(
                username: username, serviceName: "ssh-connection",
                offer: .privateKey(.init(privateKey: key))))
    }
}

private final class ConnectionErrors: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    let startup: StartupCompletion
    init(startup: StartupCompletion) { self.startup = startup }
    func channelActive(context: ChannelHandlerContext) {
        startup.progress(.negotiatingSSH)
        context.fireChannelActive()
    }
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            startup.event(.note("public-key authentication succeeded"))
            if startup.authenticationOnly { startup.finish(.success(())) } else { startup.progress(.sessionChannel) }
        }
        context.fireUserInboundEventTriggered(event)
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        startup.finish(.failure(error))
        context.close(promise: nil)
    }
}

private final class PTYHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    let command: String?
    let columns: Int
    let rows: Int
    let startup: StartupCompletion
    let output: @Sendable (Data) async -> Void
    let remoteStage: ConnectionStage
    let requiresPTY: Bool
    private var acceptedPTY = false
    private var acceptedCommand = false
    private var pending: [Data] = []
    private var pendingBytes = 0
    private var delivering = false

    init(
        command: String?, columns: Int, rows: Int, startup: StartupCompletion,
        output: @escaping @Sendable (Data) async -> Void, remoteStage: ConnectionStage, requiresPTY: Bool
    ) {
        self.remoteStage = remoteStage
        self.requiresPTY = requiresPTY
        self.command = command
        self.columns = columns
        self.rows = rows
        self.startup = startup
        self.output = output
    }

    func channelActive(context: ChannelHandlerContext) {
        startup.event(.note("session channel opened"))
        if !requiresPTY, let command {
            acceptedPTY = true
            startup.progress(remoteStage)
            context.triggerUserOutboundEvent(
                SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true), promise: nil)
            context.read()
            return
        }
        startup.progress(.pty)
        context.triggerUserOutboundEvent(
            SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true, term: "xterm-256color", terminalCharacterWidth: columns,
                terminalRowHeight: rows, terminalPixelWidth: 0, terminalPixelHeight: 0,
                terminalModes: .init([:])
            ), promise: nil)
        context.read()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is ChannelSuccessEvent {
            if !acceptedPTY {
                acceptedPTY = true
                startup.event(.note("PTY allocated"))
                startup.progress(remoteStage)
                if let command {
                    context.triggerUserOutboundEvent(
                        SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true), promise: nil)
                } else {
                    context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true), promise: nil)
                }
            } else if !acceptedCommand {
                acceptedCommand = true
                startup.event(.note("remote command accepted"))
                startup.progress(.awaitingOutput)
                startup.finish(.success(()))
            }
        } else if let exit = event as? SSHChannelRequestEvent.ExitStatus {
            startup.event(.remoteExit(exit.exitStatus))
            if exit.exitStatus != 0 {
                startup.progress(remoteStage)
                startup.finish(.failure(ConnectionFailure(stage: remoteStage, code: "remoteExit=\(exit.exitStatus)")))
            }
        } else if event is SSHChannelRequestEvent.ExitSignal {
            startup.event(.remoteExit(-1))
        } else if event is ChannelFailureEvent {
            startup.finish(.failure(SSHConnectionError.requestRejected))
            context.close(promise: nil)
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let packet = unwrapInboundIn(data)
        guard packet.type == .channel || packet.type == .stdErr,
            case .byteBuffer(let buffer) = packet.data
        else {
            fail(context, SSHConnectionError.invalidChannel)
            return
        }
        let data = Data(buffer.readableBytesView)
        guard pendingBytes + data.count <= 1024 * 1024 else {
            fail(context, SSHConnectionError.outputLimitExceeded)
            return
        }
        pending.append(data)
        pendingBytes += data.count
        deliver(context)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        if !delivering && pending.isEmpty { context.read() }
    }

    private func deliver(_ context: ChannelHandlerContext) {
        guard !delivering, !pending.isEmpty else { return }
        delivering = true
        let data = pending.removeFirst()
        let bound = NIOLoopBound((self, context), eventLoop: context.eventLoop)
        let channel = context.channel
        let output = output
        Task {
            await output(data)
            channel.eventLoop.execute {
                let (handler, context) = bound.value
                handler.pendingBytes -= data.count
                handler.delivering = false
                if !handler.pending.isEmpty { handler.deliver(context) } else if channel.isActive { context.read() }
            }
        }
    }

    private func fail(_ context: ChannelHandlerContext, _ error: Error) {
        startup.finish(.failure(error))
        context.fireErrorCaught(error)
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) { fail(context, error) }
    func channelInactive(context: ChannelHandlerContext) {
        startup.finish(.failure(SSHConnectionError.disconnected))
        context.fireChannelInactive()
    }
}

extension ConnectionFailure {
    public static func capture(_ error: Error, stage: ConnectionStage) -> ConnectionFailure {
        if let failure = error as? ConnectionFailure { return failure }
        if let value = error as? SSHConnectionError {
            let actual: ConnectionStage =
                value == .hostKeyMismatch
                ? .hostVerification : (value == .authenticationRejected ? .authentication : stage)
            return .init(
                stage: actual, code: String(describing: value),
                retryable: value == .timedOut || value == .disconnected)
        }
        if let value = error as? NIOSSHError {
            return .init(stage: stage, code: "NIOSSHError.\(value.type)")
        }
        if let value = error as? IOError {
            return .init(stage: stage, code: "IOError errno=\(value.errnoCode)", retryable: true)
        }
        // Do not export localizedDescription: it can include server-controlled data.
        let ns = error as NSError
        return .init(
            stage: stage, code: "\(String(reflecting: type(of: error))) code=\(ns.code)",
            retryable: stage == .openingTransport)
    }
}

/// Cancellation closes a created channel immediately, including during negotiation.
/// DNS before channel creation remains bounded by the bootstrap connect timeout.
private final class ConnectionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var channel: Channel?
    private var cancelled = false
    func register(_ value: Channel) {
        lock.lock()
        channel = value
        let close = cancelled
        lock.unlock()
        if close { value.close(promise: nil) }
    }
    func cancel() {
        lock.lock()
        cancelled = true
        let value = channel
        lock.unlock()
        value?.close(promise: nil)
    }
}
