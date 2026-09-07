import Foundation

/// The SSH command is chosen locally; terminal output is never command input.
public enum SessionIntent: Sendable, Equatable {
    case shell
    case authenticationProbe
    case diagnosticEcho
    case diagnosticShell
    case attach(name: String)
    case createOrAttach(name: String)

    public static func selected(
        useTmux: Bool, diagnosticMode: String, name: String,
        create: Bool, reattaching: Bool
    ) throws -> SessionIntent {
        if useTmux { return create && !reattaching ? .createOrAttach(name: name) : .attach(name: name) }
        switch diagnosticMode {
        case "auth": return .authenticationProbe
        case "echo": return .diagnosticEcho
        case "clean-shell": return .diagnosticShell
        case "shell": return .shell
        default: throw SessionConfigurationError.invalidDiagnosticMode
        }
    }

    public func command(tmuxExecutable: String = "tmux") throws -> String? {
        if self == .shell || self == .authenticationProbe { return nil }
        if case .diagnosticEcho = self { return "printf 'MOSHDECK_OK\\n'" }
        if case .diagnosticShell = self { return "exec /bin/zsh -f" }
        guard !tmuxExecutable.isEmpty,
            !tmuxExecutable.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw SessionConfigurationError.invalidExecutable
        }
        let name: String
        let create: Bool
        switch self {
        case .shell, .authenticationProbe, .diagnosticEcho, .diagnosticShell: return nil
        case .attach(let value):
            name = value
            create = false
        case .createOrAttach(let value):
            name = value
            create = true
        }
        // A deliberately small profile format avoids shell and tmux target syntax.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard !name.isEmpty, name.utf8.count <= 64,
            name.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw SessionConfigurationError.invalidSessionName
        }
        let executable = "'" + tmuxExecutable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return create
            ? "exec \(executable) new-session -A -s '\(name)'" : "exec \(executable) attach-session -t '=\(name)'"
    }

    public var reconnectIntent: SessionIntent {
        switch self {
        case .createOrAttach(let name): .attach(name: name)
        default: self
        }
    }
}

public enum SessionConfigurationError: Error, Sendable {
    case invalidDiagnosticMode
    case invalidSessionName
    case invalidExecutable
}

/// A generation changes before starting/ending a connection. Old asynchronous
/// completions may still arrive, but must never enable input or submit a prompt.
public struct ConnectionGeneration: Sendable {
    public private(set) var token = UUID()
    public private(set) var isLive = false

    public init() {}

    @discardableResult
    public mutating func begin() -> UUID {
        token = UUID()
        isLive = false
        return token
    }

    public mutating func ready(_ candidate: UUID) -> Bool {
        guard candidate == token else { return false }
        isLive = true
        return true
    }

    public mutating func invalidate() { _ = begin() }

    public func permitsInput(for candidate: UUID) -> Bool {
        candidate == token && isLive
    }
}
