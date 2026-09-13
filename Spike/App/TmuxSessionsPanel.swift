import MoshDeckCore
import SwiftUI

/// A modal overlay leaves the terminal view in its existing hierarchy.
struct TmuxSessionsPanel: View {
    let sessions: [TmuxSessionSummary]
    let loading: Bool
    let error: String?
    let reconnectTarget: String
    let canSelect: Bool
    let select: (TmuxSessionSummary) -> Void
    let refresh: () -> Void
    let close: () -> Void
    let terminalPicker: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Button(action: close) { Color.black.opacity(0.35) }
                    .buttonStyle(.plain).accessibilityLabel("Close sessions")
                VStack(spacing: 0) {
                    HStack {
                        Text("Sessions").font(.headline)
                        Spacer()
                        Button(action: refresh) {
                            Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Refresh sessions").disabled(loading || !canSelect)
                        Button(action: close) {
                            Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("Close sessions")
                    }.padding(.leading)
                    List {
                        Section {
                            Text(
                                "Selecting updates the reconnect target. Mac clients stay attached."
                            )
                            .font(.footnote)
                            Text("Reconnect target: \(reconnectTarget)").font(.footnote)
                        }
                        if loading {
                            ProgressView("Loading sessions…")
                        } else if let error {
                            Text(error).font(.callout)
                        } else if sessions.isEmpty {
                            Text("No sessions found. Create one in a shell on your Mac, then refresh.")
                        }
                        ForEach(sessions) { session in
                            Button {
                                select(session)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(
                                        "\(session.windows) \(session.windows == 1 ? "window" : "windows") · \(session.attachedClients) \(session.attachedClients == 1 ? "client" : "clients")"
                                    )
                                    .font(.caption).foregroundStyle(.secondary)
                                    if !session.canAttach {
                                        Text("Use the terminal picker for this name.").font(.caption)
                                    }
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }.disabled(!canSelect || !session.canAttach)
                                .accessibilityIdentifier("session.option.\(session.name)")
                        }
                        Section {
                            Button("Open terminal picker (Ctrl-B, s)", action: terminalPicker)
                                .disabled(!canSelect)
                        }
                    }.listStyle(.insetGrouped)
                }
                .frame(width: min(340, max(0, geometry.size.width - 24)))
                .background(.regularMaterial)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, close)
            }
        }
    }
}
