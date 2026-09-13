import Foundation

public struct TmuxSessionSummary: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let windows: Int
    public let attachedClients: Int
    public var canAttach: Bool { (try? SessionIntent.attach(name: name).command()) != nil }
}

public enum TmuxListingError: Error, Sendable, Equatable {
    case invalidResponse
    case remoteExit(Int)
    case outputLimit, timedOut
}

/// Bounded session metadata, kept separate from terminal output and diagnostics.
public enum TmuxSessionListing {
    public static let maximumBytes = 32 * 1024

    public static func command(executable: String) throws -> String {
        // Reuse the profile's executable validation and quoting rules.
        _ = try SessionIntent.attach(name: "validation").command(tmuxExecutable: executable)
        let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // Force UTF-8 names even when a noninteractive SSH login has no UTF-8 locale.
        return "exec \(quoted) -u list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}'"
    }

    public static func parse(_ data: Data) throws -> [TmuxSessionSummary] {
        guard data.count <= maximumBytes else { throw TmuxListingError.outputLimit }
        guard let text = String(data: data, encoding: .utf8) else { throw TmuxListingError.invalidResponse }
        var names = Set<String>()
        var sessions: [TmuxSessionSummary] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { throw TmuxListingError.invalidResponse }
            let name = fields.dropLast(2).joined(separator: "|")
            guard !name.isEmpty, name.utf8.count <= 256,
                !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                let windows = Int(fields[fields.count - 2]), windows > 0,
                let clients = Int(fields[fields.count - 1]), clients >= 0,
                names.insert(name).inserted, sessions.count < 256
            else { throw TmuxListingError.invalidResponse }
            sessions.append(.init(name: name, windows: windows, attachedClients: clients))
        }
        return sessions.sorted { $0.name < $1.name }
    }
}
