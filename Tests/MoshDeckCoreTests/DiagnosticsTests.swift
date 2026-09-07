import Foundation
import Testing

@testable import MoshDeckCore
@testable import NIOSSH

struct DiagnosticsTests {
    @Test func underlyingServerTextNeverEntersExportedFailure() {
        let untrusted = "SYNTHETIC_PRIVATE_PROMPT_DO_NOT_EXPORT"
        let error = NSError(
            domain: untrusted, code: 42,
            userInfo: [NSLocalizedDescriptionKey: untrusted, NSDebugDescriptionErrorKey: untrusted])
        let failure = ConnectionFailure.capture(error, stage: .openingTransport)
        var lifecycle = ConnectionLifecycle()
        let id = lifecycle.begin()
        lifecycle.fail(id, failure)
        lifecycle.closed(id)
        #expect(!failure.message.contains(untrusted))
        #expect(!lifecycle.diagnostics.contains(untrusted))
        #expect(lifecycle.diagnostics.contains("42"))
        #expect(lifecycle.firstFailure == failure)
    }

    @Test(arguments: ConnectionStage.allCases)
    func primaryFailureMessageDoesNotExposeInternalCodes(stage: ConnectionStage) {
        let failure = ConnectionFailure(stage: stage, code: "libraryInternalCode=987654")
        #expect(!failure.title.isEmpty)
        #expect(!failure.message.contains("987654"))
        var lifecycle = ConnectionLifecycle()
        let id = lifecycle.begin()
        lifecycle.fail(id, failure)
        #expect(lifecycle.diagnostics.contains("libraryInternalCode=987654"))
        #expect(lifecycle.firstFailure == failure)
    }

    @Test func tcpShutdownRemainsRetryableAfterCleanup() {
        let failure = ConnectionFailure.capture(NIOSSHError.tcpShutdown, stage: .openingTransport)
        #expect(failure.retryable)
        var lifecycle = ConnectionLifecycle()
        let id = lifecycle.begin()
        lifecycle.accepted(id)
        lifecycle.receivedOutput(id)
        lifecycle.fail(id, failure)
        lifecycle.closed(id)
        #expect(lifecycle.firstFailure == failure)
        #expect(lifecycle.reachedConnected)
    }

    @Test func sshSecurityFailuresRemainNonRetryable() {
        let failure = ConnectionFailure.capture(NIOSSHError.invalidUserAuthSignature, stage: .authentication)
        #expect(!failure.retryable)
        #expect(!ConnectionFailure.capture(SSHConnectionError.hostKeyMismatch, stage: .hostVerification).retryable)
        #expect(!ConnectionFailure.capture(SSHConnectionError.authenticationRejected, stage: .authentication).retryable)
    }

    @Test func diagnosticHistoryIsBounded() {
        var lifecycle = ConnectionLifecycle()
        _ = lifecycle.begin()
        for index in 0..<150 { lifecycle.note("fixture stage index=\(index)") }
        #expect(lifecycle.timeline.count == 100)
        #expect(lifecycle.timeline.last?.contains("index=149") == true)
    }
}
