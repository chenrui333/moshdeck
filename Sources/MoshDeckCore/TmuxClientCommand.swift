import Foundation

public struct TmuxClientSnapshot: Sendable, Equatable {
    public let currentSession: String
    public let sessions: [TmuxSessionSummary]

    static func parse(_ data: Data) throws -> Self {
        guard let newline = data.firstIndex(of: 10), newline < 257,
            let current = String(data: data[..<newline], encoding: .utf8), !current.isEmpty
        else { throw TmuxListingError.invalidResponse }
        let sessions = try TmuxSessionListing.parse(Data(data[data.index(after: newline)...]))
        guard sessions.contains(where: { $0.name == current }) else { throw TmuxListingError.invalidResponse }
        return .init(currentSession: current, sessions: sessions)
    }
}

/// OpenSSH forks the PTY client and exec-channel shell from the same per-connection
/// server process. Match that parent PID, requiring exactly one tmux client. Never
/// guess from session name, terminal size, most-recent client, or another login.
/// Unsupported server process layouts fail closed; ordinary terminal access works.
enum TmuxClientCommand {
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func snapshot(executable: String) throws -> String {
        let prefix = try identify(executable: executable)
        let tmux = quote(executable)
        return "exec /bin/sh -c "
            + quote(
                prefix + """

                    current_session || exit 73
                    exec \(tmux) -u list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}'
                    """)
    }

    static func switchSession(to target: String, from source: String, executable: String) throws -> String {
        _ = try SessionIntent.attach(name: target).command(tmuxExecutable: executable)
        _ = try SessionIntent.attach(name: source).command(tmuxExecutable: executable)
        let prefix = try identify(executable: executable)
        let tmux = quote(executable)
        return "exec /bin/sh -c "
            + quote(
                prefix + """

                    current=$(current_session) || exit 73
                    [ "$current" = \(quote(source)) ] || exit 74
                    \(tmux) switch-client -c "$client" -t \(quote("=" + target)) || exit 75
                    current_session
                    """)
    }

    private static func identify(executable: String) throws -> String {
        _ = try SessionIntent.attach(name: "validation").command(tmuxExecutable: executable)
        return """
            set -f
            connection_parent() {
                walk=$1
                depth=0
                while [ "$depth" -lt 8 ]; do
                    label=$(/bin/ps -o comm= -p "$walk") || return 1
                    case "$label" in sshd:*@*|sshd-session:*@*|*/sshd:*@*|*/sshd-session:*@*) printf '%s\\n' "$walk"; return 0;; esac
                    walk=$(/bin/ps -o ppid= -p "$walk") || return 1
                    depth=$((depth + 1))
                done
                return 1
            }
            owner=$(connection_parent "$$") || exit 71
            peers=$(\(quote(executable)) list-clients -F '#{client_pid} #{client_tty}') || exit 70
            client=
            matches=0
            while read -r pid tty; do
                case "$pid" in ''|*[!0-9]*) continue;; esac
                case "$tty" in /dev/*) ;; *) continue;; esac
                case "$tty" in *[!a-zA-Z0-9/_-]*) continue;; esac
                parent=$(connection_parent "$pid") || continue
                if [ "$parent" -eq "$owner" ] 2>/dev/null; then
                    client=$tty
                    matches=$((matches + 1))
                fi
            done <<MOSHDECK_CLIENTS
            $peers
            MOSHDECK_CLIENTS
            [ "$matches" -eq 1 ] || exit 72
            current_session() {
                states=$(\(quote(executable)) -u list-clients -F '#{client_tty}|#{client_session}') || return 1
                while IFS='|' read -r tty name; do
                    if [ "$tty" = "$client" ]; then printf '%s\\n' "$name"; return 0; fi
                done <<MOSHDECK_STATES
            $states
            MOSHDECK_STATES
                return 1
            }
            """
    }
}
