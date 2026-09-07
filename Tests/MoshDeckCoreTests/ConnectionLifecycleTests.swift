import Foundation
import Testing

@testable import MoshDeckCore

struct ConnectionLifecycleTests {
    @Test func diagnosticSelectionActuallyChangesTransportIntent() throws {
        #expect(
            try SessionIntent.selected(
                useTmux: false, diagnosticMode: "auth", name: "work", create: false, reattaching: false)
                == .authenticationProbe)
        #expect(
            try SessionIntent.selected(
                useTmux: false, diagnosticMode: "echo", name: "work", create: false, reattaching: false)
                == .diagnosticEcho)
        #expect(
            try SessionIntent.selected(
                useTmux: false, diagnosticMode: "clean-shell", name: "work", create: false, reattaching: false)
                == .diagnosticShell)
        #expect(
            try SessionIntent.selected(
                useTmux: true, diagnosticMode: "auth", name: "work", create: true, reattaching: true)
                == .attach(name: "work"))
    }

    @Test func rootAuthenticationFailureSurvivesCleanup() {
        var model = ConnectionLifecycle()
        let id = model.begin()
        let root = ConnectionFailure(stage: .authentication, code: "publicKeyRejected")
        model.fail(id, root)
        model.closed(id)
        model.fail(id, .init(stage: .openingTransport, code: "channelClosed", retryable: true))
        #expect(model.state == .failed(root))
        #expect(model.firstFailure == root)
    }
    @Test func staleAttemptCannotChangeRetry() {
        var model = ConnectionLifecycle()
        let old = model.begin()
        model.fail(old, .init(stage: .openingTransport, code: "timeout", retryable: true))
        let current = model.begin()
        model.closed(old)
        model.progress(old, .authentication)
        model.fail(old, .init(stage: .authentication, code: "late"))
        #expect(model.attemptID == current)
        #expect(model.state == .starting(.preparation))
        #expect(model.firstFailure == nil)
    }
    @Test func retryUsesExistingAppUnlockWithoutForegroundExpiry() {
        let now = Date(timeIntervalSince1970: 1000)
        var lock = AppLockPolicy(grace: 300)
        #expect(!lock.permitsAccess(at: now))
        lock.beginUnlock()
        lock.unlocked(at: now)
        var connection = ConnectionLifecycle()
        let first = connection.begin()
        connection.fail(first, .init(stage: .openingTransport, code: "reset", retryable: true))
        _ = connection.begin()
        #expect(lock.permitsAccess(at: now.addingTimeInterval(20)))
        #expect(lock.permitsAccess(at: now.addingTimeInterval(3600)))
        lock.lock()
        #expect(!lock.permitsAccess(at: now))
    }
    @Test func commandAcceptanceNeedsInteractiveOutput() {
        var model = ConnectionLifecycle()
        let id = model.begin()
        model.accepted(id)
        #expect(!model.isLive)
        model.receivedOutput(id)
        #expect(model.isLive)
        model.closed(id)
        #expect(model.state == .reconnecting(0))
        #expect(model.firstFailure == nil)
    }
    @Test func outputBeforeExecAcceptanceDoesNotPrematurelyConnect() {
        var model = ConnectionLifecycle()
        let id = model.begin()
        model.receivedOutput(id)
        #expect(!model.isLive)
        model.accepted(id)
        #expect(model.isLive)
    }
    @Test func cancellationIsNotFailureAndInvalidatesCallbacks() {
        var model = ConnectionLifecycle()
        let id = model.begin()
        model.cancel()
        model.closed(id)
        model.fail(id, .init(stage: .openingTransport, code: "closed"))
        #expect(model.state == .cancelled)
        #expect(model.firstFailure == nil)
    }
    @Test func authAndHostMismatchAreNeverRetryable() {
        let auth = ConnectionFailure.capture(SSHConnectionError.authenticationRejected, stage: .sessionChannel)
        let host = ConnectionFailure.capture(SSHConnectionError.hostKeyMismatch, stage: .negotiatingSSH)
        #expect(auth.stage == .authentication && !auth.retryable)
        #expect(host.stage == .hostVerification && !host.retryable)
    }
}
