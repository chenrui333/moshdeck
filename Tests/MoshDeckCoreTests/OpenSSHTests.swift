#if os(macOS)
    import Crypto
    import Darwin
    import Foundation
    import Testing
    @testable import MoshDeckCore

    private actor ReceivedOutput {
        private var bytes = Data()
        func append(_ data: Data) { bytes.append(data) }
        func text() -> String { String(decoding: bytes, as: UTF8.self) }
        func waitFor(_ marker: String) async throws {
            for _ in 0..<200 {
                if text().contains(marker) { return }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw FixtureError.outputTimeout
        }
    }

    private enum FixtureError: Error { case commandFailed, socketFailed, outputTimeout, serverExited }

    private final class OpenSSHFixture {
        let directory: URL
        let server = Process()
        let port: Int
        let identity: SSHIdentity
        let hostKey: String
        private let log: FileHandle

        init(allowExec: Bool = false) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "moshdeck-sshd-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            identity = try SSHIdentity()
            let publicKey = directory.appendingPathComponent("authorized_keys")
            try (identity.publicKey + "\n").write(to: publicKey, atomically: true, encoding: .utf8)
            let host = directory.appendingPathComponent("host")
            let generator = Process()
            generator.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
            generator.arguments = ["-q", "-t", "ed25519", "-N", "", "-f", host.path]
            try generator.run()
            generator.waitUntilExit()
            guard generator.terminationStatus == 0 else { throw FixtureError.commandFailed }
            hostKey = try String(contentsOf: host.appendingPathExtension("pub"), encoding: .utf8)
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            guard sock >= 0 else { throw FixtureError.socketFailed }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let bound: Bool = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(sock, $0, length) == 0 && getsockname(sock, $0, &length) == 0
                }
            }
            Darwin.close(sock)
            guard bound else { throw FixtureError.socketFailed }
            port = Int(UInt16(bigEndian: address.sin_port))
            let config = directory.appendingPathComponent("sshd_config")
            var forcedCommand =
                "/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=\(directory.path) TERM=xterm-256color /bin/sh"
            if allowExec {
                let runner = directory.appendingPathComponent("exec-fixture.sh")
                try """
                exec /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME='\(directory.path)' TERM=xterm-256color /bin/sh -c "$SSH_ORIGINAL_COMMAND"
                """.write(to: runner, atomically: true, encoding: .utf8)
                forcedCommand = "/bin/sh \(runner.path)"
            }
            try """
            ListenAddress 127.0.0.1
            Port \(port)
            HostKey \(host.path)
            PidFile \(directory.appendingPathComponent("sshd.pid").path)
            AuthorizedKeysFile \(publicKey.path)
            ForceCommand \(forcedCommand)
            StrictModes no
            UsePAM no
            UseDNS no
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            PermitRootLogin no
            HostKeyAlgorithms ssh-ed25519
            PubkeyAcceptedAlgorithms ssh-ed25519
            LogLevel ERROR
            """.write(to: config, atomically: true, encoding: .utf8)
            let logURL = directory.appendingPathComponent("server.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            log = try FileHandle(forWritingTo: logURL)
            server.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
            server.arguments = ["-D", "-e", "-f", config.path]
            server.standardOutput = log
            server.standardError = log
            try server.run()
        }

        func start() async throws {
            try await Task.sleep(for: .milliseconds(300))
            guard server.isRunning else {
                // Contains fixture server diagnostics only, never terminal/user input.
                let text = try String(contentsOf: directory.appendingPathComponent("server.log"), encoding: .utf8)
                Issue.record("Isolated OpenSSH failed: \(text)")
                throw FixtureError.serverExited
            }
        }

        var profile: SSHProfile {
            SSHProfile(host: "127.0.0.1", port: port, username: NSUserName(), trustedHostKey: hostKey)
        }

        deinit { cleanup() }

        func cleanup() {
            // Do not waitUntilExit from a Swift task's destructor: Foundation's
            // run-loop wait can stall even after sshd has exited. Request exit,
            // then remove our resources now; a termination callback can be lost
            // when the test runner exits. Child processes own their open FDs.
            if server.isRunning { server.terminate() }
            try? log.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Suite(.serialized)
    struct OpenSSHTests {
        @Test func cancellationClosesStalledSSHHandshake() async throws {
            let listener = socket(AF_INET, SOCK_STREAM, 0)
            guard listener >= 0 else { throw FixtureError.socketFailed }
            defer { Darwin.close(listener) }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let bound = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(listener, $0, length) == 0 && getsockname(listener, $0, &length) == 0
                }
            }
            guard bound, listen(listener, 1) == 0 else { throw FixtureError.socketFailed }
            let identity = try SSHIdentity()
            let profile = SSHProfile(
                host: "127.0.0.1", port: Int(UInt16(bigEndian: address.sin_port)),
                username: "fixture", trustedHostKey: identity.publicKey)
            let attempt = Task {
                try await SSHConnection.connect(
                    profile: profile, identity: identity, columns: 80, rows: 24, output: { _ in })
            }
            try await Task.sleep(for: .milliseconds(200))
            let start = ContinuousClock.now
            attempt.cancel()
            do {
                let connection = try await attempt.value
                await connection.close()
                Issue.record("Handshake completed despite the server never sending an SSH banner")
            } catch {}
            #expect(start.duration(to: .now) < .seconds(2))
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MOSHDECK_REAL_MAC_SSH"] == "1"))
        func optInRealMacOpenSSH() async throws {
            guard ProcessInfo.processInfo.environment["MOSHDECK_REAL_MAC_SSH"] == "1" else { return }
            let identity = try SSHIdentity()
            let entry = identity.publicKey + " moshdeck-temporary-interop-\(UUID().uuidString)"
            let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/authorized_keys")
            func editAuthorization(remove: Bool) throws {
                let handle = try FileHandle(forUpdating: file)
                defer { try? handle.close() }
                guard flock(handle.fileDescriptor, LOCK_EX) == 0 else { throw FixtureError.commandFailed }
                defer { flock(handle.fileDescriptor, LOCK_UN) }
                let old = try handle.readToEnd() ?? Data()
                var content = String(decoding: old, as: UTF8.self)
                if remove {
                    content = content.replacingOccurrences(of: entry + "\n", with: "")
                } else {
                    if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
                    content += entry + "\n"
                }
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: Data(content.utf8))
                try handle.truncate(atOffset: UInt64(content.utf8.count))
                try handle.synchronize()
            }
            try editAuthorization(remove: false)
            defer {
                do { try editAuthorization(remove: true) } catch {
                    Issue.record("Temporary test public-key cleanup failed")
                }
            }
            let hostKey = try String(contentsOfFile: "/etc/ssh/ssh_host_ed25519_key.pub", encoding: .utf8)
            let output = ReceivedOutput()
            let mode = ProcessInfo.processInfo.environment["MOSHDECK_REAL_MAC_MODE"] ?? "shell"
            var intent: SessionIntent =
                mode == "echo" ? .diagnosticEcho : (mode == "clean-shell" ? .diagnosticShell : .shell)
            if mode == "auth" { intent = .authenticationProbe }
            if mode == "tmux" { intent = .attach(name: "moshdeck-spike") }
            let connection = try await SSHConnection.connect(
                profile: SSHProfile(
                    host: "127.0.0.1", username: NSUserName(), trustedHostKey: hostKey, intent: intent,
                    tmuxExecutable: "/opt/homebrew/bin/tmux"),
                identity: identity, columns: 80, rows: 24,
                output: { await output.append($0) },
                event: { event in
                    switch event {
                    case .closed: break
                    case .stage(let stage): print("Real Mac SSH stage=\(stage.rawValue)")
                    case .note(let note): print("Real Mac SSH \(note)")
                    case .remoteExit(let status): print("Real Mac SSH exit=\(status)")
                    }
                })
            defer { Task { await connection.close() } }
            if mode == "auth" {
                await connection.close()
                return
            }
            if mode == "echo" {
                try await output.waitFor("MOSHDECK_OK")
            } else {
                try await Task.sleep(for: .seconds(2))
                try await connection.send(Data("printf 'MOSHDECK_%s\\n' REAL_MAC_OK\r".utf8))
                for _ in 0..<30 {
                    if await output.text().contains("MOSHDECK_REAL_MAC_OK") { break }
                    try await Task.sleep(for: .seconds(1))
                }
                let received = await output.text()
                print(
                    "Real Mac output bytes=\(received.utf8.count); expected marker present=\(received.contains("MOSHDECK_REAL_MAC_OK"))"
                )
                #expect(received.contains("MOSHDECK_REAL_MAC_OK"))
            }
            await connection.close()
        }

        @Test func verifiedPTYIOResizeAndWrongKeyRejection() async throws {
            let fixture = try OpenSSHFixture()
            defer { fixture.cleanup() }
            try await fixture.start()
            let output = ReceivedOutput()
            let connection = try await SSHConnection.connect(
                profile: fixture.profile, identity: fixture.identity,
                columns: 80, rows: 24, output: { await output.append($0) })
            // Split the marker in the command so terminal echo alone cannot pass.
            try await connection.send(Data("printf 'MOSHDECK_%s\\n' 'PTY_OK'\r".utf8))
            try await output.waitFor("MOSHDECK_PTY_OK")
            try await connection.resize(columns: 93, rows: 31)
            try await connection.send(Data("stty size\r".utf8))
            try await output.waitFor("31 93")
            try await connection.checkLiveness()
            await connection.close()
            await #expect(throws: SSHConnectionError.disconnected) {
                try await connection.send(Data("must not send".utf8))
            }
            var impostor = fixture.profile
            impostor.trustedHostKey = try SSHIdentity().publicKey
            do {
                let unexpected = try await SSHConnection.connect(
                    profile: impostor, identity: fixture.identity,
                    columns: 80, rows: 24, output: { _ in })
                await unexpected.close()
                Issue.record("Host-key substitution was accepted")
            } catch {
                #expect((error as? ConnectionFailure)?.stage == .hostVerification)
                #expect((error as? ConnectionFailure)?.code == "hostKeyMismatch")
            }
        }

        @Test func sessionListingUsesSeparateChannelAndPreservesTerminal() async throws {
            let fixture = try OpenSSHFixture(allowExec: true)
            defer { fixture.cleanup() }
            try await fixture.start()
            let output = ReceivedOutput()
            var profile = fixture.profile
            profile.intent = .diagnosticShell
            let connection = try await SSHConnection.connect(
                profile: profile, identity: fixture.identity, columns: 80, rows: 24,
                output: { await output.append($0) })
            let script = fixture.directory.appendingPathComponent("list-fixture")
            func writeScript(_ body: String) throws {
                try ("#!/bin/sh\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            }
            try writeScript("printf 'unique-session-marker|1|2\\n'")
            let rows = try await connection.listTmuxSessions(executable: script.path)
            #expect(rows.map(\.name) == ["unique-session-marker"])
            #expect(rows.first?.attachedClients == 2)
            #expect(!(await output.text()).contains("unique-session-marker"))
            try writeScript("exit 7")
            await #expect(throws: TmuxListingError.remoteExit(7)) {
                try await connection.listTmuxSessions(executable: script.path)
            }
            try writeScript("head -c 40000 /dev/zero")
            await #expect(throws: TmuxListingError.outputLimit) {
                try await connection.listTmuxSessions(executable: script.path)
            }
            try writeScript("sleep 10")
            await #expect(throws: TmuxListingError.timedOut) {
                try await connection.listTmuxSessions(executable: script.path)
            }
            let request = Task { try await connection.listTmuxSessions(executable: script.path) }
            try await Task.sleep(for: .milliseconds(100))
            request.cancel()
            do {
                _ = try await request.value
                Issue.record("Cancelled listing completed")
            } catch { #expect(error is CancellationError) }
            // The auxiliary failure and cancellation must not close the PTY.
            try await connection.send(Data("echo TERMINAL_REMAINS_LIVE\r".utf8))
            try await output.waitFor("TERMINAL_REMAINS_LIVE")
            try await connection.checkLiveness()
            await connection.close()
        }

        @Test func missingTmuxSessionFailsWithoutReplacingIt() async throws {
            let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"]
            let executable = try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0) })
            let fixture = try OpenSSHFixture(allowExec: true)
            defer { fixture.cleanup() }
            try await fixture.start()
            let socketName = "moshdeck-test-\(UUID().uuidString)"
            func tmux(_ arguments: [String]) throws -> Int32 {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = ["-L", socketName, "-f", "/dev/null"] + arguments
                process.environment = [
                    "PATH": "/usr/bin:/bin", "HOME": fixture.directory.path, "TERM": "xterm-256color",
                ]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            }
            #expect(try tmux(["new-session", "-d", "-s", "retained", "exec /bin/sleep 600"]) == 0)
            defer { _ = try? tmux(["kill-server"]) }
            let wrapper = fixture.directory.appendingPathComponent("tmux-fixture")
            try "#!/bin/sh\nexec '\(executable)' -L '\(socketName)' -f /dev/null \"$@\"\n"
                .write(to: wrapper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
            let (events, continuation) = AsyncStream<ConnectionEvent>.makeStream()
            var profile = fixture.profile
            profile.intent = .createOrAttach(name: "missing").reconnectIntent
            profile.tmuxExecutable = wrapper.path
            var connection: SSHConnection?
            do {
                connection = try await SSHConnection.connect(
                    profile: profile, identity: fixture.identity, columns: 80, rows: 24,
                    output: { _ in }, event: { continuation.yield($0) })
                let status = try await withThrowingTaskGroup(of: Int.self) { group in
                    group.addTask {
                        for await event in events {
                            if case .remoteExit(let code) = event { return code }
                        }
                        throw FixtureError.outputTimeout
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(5))
                        throw FixtureError.outputTimeout
                    }
                    defer { group.cancelAll() }
                    return try await #require(group.next())
                }
                #expect(status != 0)
            } catch let failure as ConnectionFailure {
                #expect(failure.stage == .tmux)
                #expect(failure.code.hasPrefix("remoteExit="))
            }
            continuation.finish()
            await connection?.close()
            #expect(try tmux(["has-session", "-t", "=missing"]) != 0)
            #expect(try tmux(["has-session", "-t", "=retained"]) == 0)
            #expect(try tmux(["new-session", "-d", "-s", "second", "exec /bin/sleep 600"]) == 0)
            #expect(try tmux(["new-session", "-d", "-s", "中文", "exec /bin/sleep 600"]) == 0)
            profile.intent = .attach(name: "retained")
            let retainedOutput = ReceivedOutput()
            let retained = try await SSHConnection.connect(
                profile: profile, identity: fixture.identity, columns: 80, rows: 24,
                output: { await retainedOutput.append($0) })
            try await retainedOutput.waitFor("retained")
            let sessions = try await retained.listTmuxSessions(executable: wrapper.path)
            #expect(sessions.map(\.name) == ["retained", "second", "中文"])
            #expect(sessions.last?.canAttach == false)
            #expect(sessions.first?.attachedClients == 1)
            await retained.close()
            #expect(try tmux(["has-session", "-t", "=retained"]) == 0)

        }

        @Test(arguments: [1024, 10 * 1024, 50 * 1024])
        func largeUnicodeInputPreservesBytes(size: Int) async throws {
            let fixture = try OpenSSHFixture()
            defer { fixture.cleanup() }
            try await fixture.start()
            let output = ReceivedOutput()
            let connection = try await SSHConnection.connect(
                profile: fixture.profile, identity: fixture.identity, columns: 80, rows: 24,
                output: { await output.append($0) })
            let seed = Data("中文 日本語 👩🏽‍💻 e\u{301}\n".utf8)
            var payload = Data()
            while payload.count + seed.count <= size { payload.append(seed) }
            payload.append(Data(repeating: 120, count: size - payload.count))
            // Exercise the bytes a bracketed paste sends, including multibyte
            // characters split between writes. This does not test Ghostty's encoder.
            var wire = Data("\u{1b}[200~".utf8)
            wire.append(payload)
            wire.append(Data("\u{1b}[201~".utf8))
            let expected = SHA256.hash(data: wire).map { String(format: "%02x", $0) }.joined()
            let command =
                "stty raw -echo; printf 'INPUT_%s\\n' READY; "
                + "/bin/dd bs=1 count=\(wire.count) 2>/dev/null | /usr/bin/shasum -a 256; "
                + "stty sane; printf 'INPUT_%s\\n' DONE\r"
            try await connection.send(Data(command.utf8))
            try await output.waitFor("INPUT_READY")
            let pipe = TerminalInputPipe(failed: { Issue.record("Synthetic paste write failed") })
            pipe.bind { try await connection.send($0) }
            for offset in stride(from: 0, to: wire.count, by: 31) {
                pipe.enqueue(wire.subdata(in: offset..<min(offset + 31, wire.count)))
            }
            await pipe.waitForDrain()
            try await output.waitFor("INPUT_DONE")
            let result = await output.text()
            #expect(result.contains(expected))
            // A shell marker after raw mode verifies normal input recovers.
            try await connection.send(Data("printf 'RECOVERED_%s\\n' SHELL\r".utf8))
            try await output.waitFor("RECOVERED_SHELL")
            pipe.stop()
            await connection.close()
        }

        @Test func syntheticOutputThroughputAndInterrupt() async throws {
            let fixture = try OpenSSHFixture()
            defer { fixture.cleanup() }
            try await fixture.start()
            let output = ReceivedOutput()
            let connection = try await SSHConnection.connect(
                profile: fixture.profile, identity: fixture.identity, columns: 80, rows: 24,
                output: { await output.append($0) })
            let row = String(repeating: "x", count: 64)
            let command =
                "printf '\nMD_BEGIN_%s\n' STREAM; /usr/bin/awk 'BEGIN { for(i=0;i<16384;i++) printf \"" + row
                + "\" }'; printf '\nMD_END_%s\n' STREAM\r"
            let start = ContinuousClock.now
            try await connection.send(Data(command.utf8))
            try await output.waitFor("MD_END_STREAM")
            let elapsed = start.duration(to: .now)
            let text = await output.text()
            let begin = try #require(text.range(of: "MD_BEGIN_STREAM\r\n"))
            let end = try #require(text.range(of: "\r\nMD_END_STREAM", range: begin.upperBound..<text.endIndex))
            let body = text[begin.upperBound..<end.lowerBound]
            #expect(body.utf8.count == 1_048_576)
            #expect(body.allSatisfy { $0 == "x" })
            print(
                "Synthetic loopback OpenSSH transfer: 1048576 payload bytes in \(elapsed). No renderer or mobile path.")
            try await connection.send(Data("sleep 30\r".utf8))
            try await Task.sleep(for: .milliseconds(250))
            try await connection.send(Data([3]))
            try await connection.send(Data("printf 'AFTER_%s\n' INTERRUPT\r".utf8))
            try await output.waitFor("AFTER_INTERRUPT")
            await connection.close()
        }

    }
#endif
