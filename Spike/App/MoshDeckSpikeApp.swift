import GhosttyTerminal
import MoshDeckCore
import SwiftUI
import UIKit

// Authenticated remote terminal, with a synthetic frontend harness in Debug only.
@main
struct MoshDeckSpikeApp: App {
    #if DEBUG
        @State private var selectedTab =
            ProcessInfo.processInfo.environment["MOSHDECK_SPIKE_HOST"] == nil ? "fixture" : "ssh"
    #endif
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                    TabView(selection: $selectedTab) {
                        TerminalHarness().tag("fixture").tabItem { Label("Fixture", systemImage: "terminal") }
                        RemoteTerminalScreen().tag("ssh").tabItem {
                            Label("SSH", systemImage: "network")
                        }
                    }
                #else
                    RemoteTerminalScreen()
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) { notification in
                if let scene = notification.object as? UIWindowScene { PrivacyCover.hide(scene) }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { notification in
                if let scene = notification.object as? UIWindowScene { PrivacyCover.reveal(scene) }
            }
        }
    }
}

#if DEBUG
    private final class ByteCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()

        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            // This captures synthetic fixture input only, never a remote session.
            if bytes.count + data.count <= 128 * 1024 { bytes.append(data) }
        }

        func take() -> Data {
            lock.lock()
            defer { lock.unlock() }
            let result = bytes
            bytes.removeAll(keepingCapacity: true)
            return result
        }
    }

#endif

// A remote host cannot read files staged in the phone container. Keep the
// harness plain text and remove drop interactions supplied by the wrapper.
@MainActor
final class PlainTextTerminalView: TerminalView {
    var acceptsTerminalInput: @MainActor () -> Bool = { true }
    private(set) var sessionSwipe: TerminalSessionSwipe?
    private lazy var mobileAccessory = TerminalKeyboardAccessory(terminal: self)

    override var inputAccessoryView: UIView? { mobileAccessory }

    override init(frame: CGRect) {
        super.init(frame: frame)
        sessionSwipe = TerminalSessionSwipe(view: self)
        for interaction in interactions where interaction is UIDropInteraction {
            removeInteraction(interaction)
        }
    }

    required init?(coder: NSCoder) { nil }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        // Do not carry armed/locked modifiers into the next editing session.
        resetStickyModifiers()
        return super.resignFirstResponder()
    }

    override func paste(_ sender: Any?) {
        if let text = UIPasteboard.general.string { _ = paste(text: text) }
    }
}

#if DEBUG
    @MainActor
    private final class HarnessModel: ObservableObject {
        let terminal: TerminalViewState
        let session: InMemoryTerminalSession
        private let capture: ByteCapture
        @Published var result = "Fixture not run"
        @Published var draft = "Inspect the current module.\nExplain the next change."
        @Published var keyResult = "Keys not checked"
        @Published var swipeSession = "work"
        @Published var swipePreview: SessionSwipePreview?
        var gesturesEnabled = true
        @Published var selection: TerminalSelectionSnapshot?
        @Published var scrollCheck = "Scroll not checked"
        private var beforeScroll: String?
        private let swipeSessions = (try? TmuxSessionListing.parse(Data("infra|1|0\nwork|2|2\n".utf8))) ?? []

        init() {
            TerminalDebugLog.disable()
            let capture = ByteCapture()
            self.capture = capture
            session = InMemoryTerminalSession(write: { capture.append($0) }, resize: { _ in })
            terminal = TerminalViewState(terminalConfiguration: safeTerminalConfiguration())
            terminal.configuration = TerminalSurfaceOptions(backend: .inMemory(session), fontSize: 14)
            terminal.makePlatformView = { [weak self] in
                let view = PlainTextTerminalView(frame: .zero)
                view.sessionSwipe?.enabled = { [weak self] in self?.gesturesEnabled == true && self?.selection == nil }
                view.sessionSwipe?.update = { [weak self] phase, delta, velocity, width in
                    guard let self else { return }
                    switch phase {
                    case .began:
                        swipePreview = SessionSwipePreview(
                            source: swipeSession,
                            target: SessionSwipe.target(in: swipeSessions, current: swipeSession, x: delta.x),
                            next: delta.x < 0, progress: 0)
                    case .changed:
                        swipePreview?.progress = min(1, abs(delta.x) / SessionSwipe.threshold(width: width))
                    case .ended:
                        if let preview = swipePreview, let target = preview.target,
                            (delta.x < 0) == preview.next,
                            SessionSwipe.commits(x: delta.x, y: delta.y, velocityX: velocity, width: width)
                        {
                            swipeSession = target.name
                        }
                        swipePreview = nil
                    case .cancelled: swipePreview = nil
                    }
                }
                return view
            }
            terminal.onTextSelectionRequest = { [weak self] request in
                self?.selection = TerminalSelectionSnapshot(text: request.text, anchor: request.anchorRange)
            }
            terminal.onClipboardConfirmationRequest = { request in
                // Synthetic paste tests are intentional. Remote clipboard operations
                // remain denied. Production composer requires explicit validation.
                request.respond(allow: request.kind == .paste)
            }
        }

        func prepareScroll() {
            for row in 0..<120 { session.receive("Synthetic scroll row \(row)\r\n") }
            session.waitForPendingOutput()
            beforeScroll = session.readViewportText()
            scrollCheck = "Scroll prepared"
        }
        func checkScroll() {
            scrollCheck =
                session.readViewportText() != beforeScroll ? "PASS: viewport scrolled" : "FAIL: viewport unchanged"
        }

        func checkAccessoryKeys() {
            // Only the synthetic session is captured. Remote input is never recorded.
            let expected = Data([3, 27, 9] + Array("\u{1b}[A\u{1b}[B\u{1b}[D\u{1b}[C".utf8))
            keyResult = capture.take() == expected ? "PASS: accessory bytes" : "FAIL: accessory bytes"
        }

        func runChecks() async {
            result = "Running fixture"
            // Wait for the actual UIKit surface, not a guessed layout delay.
            for _ in 0..<100 {
                if terminal.surfaceSize?.columns ?? 0 > 0 { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard terminal.surfaceSize?.columns ?? 0 > 0 else {
                result = "FAIL: no terminal surface"
                return
            }
            var failures: [String] = []
            let fixture =
                "\u{1b}c\u{1b}[2J\u{1b}[HASCII\r\n中文 e\u{301} 👩🏽‍💻\r\n\u{1b}[38;2;50;200;100mTRUECOLOR\u{1b}[0m\r\n"
            // Exercise split escape sequences and split UTF-8 through the real parser.
            for byte in fixture.utf8 { session.receive(Data([byte])) }
            session.waitForPendingOutput()
            let screen = session.readViewportText() ?? ""
            if !screen.contains("ASCII") || !screen.contains("中文") || !screen.contains("TRUECOLOR") {
                failures.append("chunked text")
            }
            session.receive("\u{1b}[?1049h\u{1b}[2J\u{1b}[HALTERNATE")
            session.waitForPendingOutput()
            if !(session.readViewportText() ?? "").contains("ALTERNATE") { failures.append("alternate enter") }
            session.receive("\u{1b}[?1049l")
            session.waitForPendingOutput()
            if !(session.readViewportText() ?? "").contains("ASCII") { failures.append("alternate restore") }

            _ = capture.take()
            terminal.sendKey(.c, modifiers: .ctrl)
            try? await Task.sleep(for: .milliseconds(150))
            if capture.take() != Data([3]) { failures.append("Ctrl-C") }

            if let view = terminal.attachedPlatformView {
                // Exercise the actual wrapper state used by its accessory bar.
                view.toggleStickyModifier(.ctrl)
                view.toggleStickyModifier(.ctrl)  // Double tap: locked, not one-shot.
                view.toggleStickyModifier(.alt)
                view.toggleStickyModifier(.command)
                _ = view.resignFirstResponder()
                if view.hasActiveStickyModifiers { failures.append("modifiers after focus loss") }
                // Keep later fixture input independent of a failed reset assertion.
                view.resetStickyModifiers()
            } else {
                failures.append("modifier platform view")
            }

            session.receive("\u{1b}[?2004h")
            session.waitForPendingOutput()
            _ = capture.take()
            let prompt = String(repeating: "synthetic prompt word ", count: 180)
            terminal.paste(text: prompt)
            try? await Task.sleep(for: .milliseconds(150))
            let pasted = capture.take()
            if pasted != Data(("\u{1b}[200~" + prompt + "\u{1b}[201~").utf8) {
                failures.append("bracketed large paste")
            }
            terminal.sendKey(.enter)
            try? await Task.sleep(for: .milliseconds(150))
            if capture.take() != Data([13]) { failures.append("Enter key") }
            session.receive("\r\nFixture checks complete.\r\n")
            result =
                failures.isEmpty
                ? "PASS: parser, alternate screen, Ctrl-C, modifier reset, paste, Enter"
                : "FAIL: " + failures.joined(separator: ", ")
        }
    }

    @MainActor
    private struct TerminalHarness: View {
        @StateObject private var model = HarnessModel()
        @Environment(\.scenePhase) private var phase
        @State private var showComposer = false
        @State private var showSessions = false
        @State private var sessionSelection = "No selection"

        var body: some View {
            VStack(spacing: 0) {
                Text("MoshDeck • synthetic frontend spike")
                    .font(.headline).padding(8)
                Text(model.result).font(.caption)
                    .accessibilityIdentifier("fixture.result").padding(4)
                Text(model.swipeSession).accessibilityIdentifier("fixture.swipe.session")
                TerminalSurfaceView(context: model.terminal).accessibilityIdentifier("fixture.terminal")
                    .overlay(alignment: .trailing) {
                        if let preview = model.swipePreview { SessionSwipePreviewView(preview: preview) }
                    }
                HStack {
                    Button("Show Keyboard") { model.terminal.requestFocus() }
                    Button("Compose") { showComposer = true }
                    Button("Run fixture") { Task { await model.runChecks() } }
                    Button("Sessions") { showSessions = true }.accessibilityValue(sessionSelection)
                }
                HStack {
                    Button("Scroll fixture") { model.prepareScroll() }
                    Button("Check scrolling") { model.checkScroll() }
                    Text(model.scrollCheck).font(.caption).accessibilityIdentifier("fixture.scroll")
                }
                HStack {
                    Button("Check key input") { model.checkAccessoryKeys() }
                    Text(model.keyResult).accessibilityIdentifier("fixture.keys")
                }.buttonStyle(.bordered).padding(6)
            }
            .accessibilityHidden(showSessions)
            .allowsHitTesting(!showSessions)
            .overlay(alignment: .leading) {
                if showSessions {
                    TmuxSessionsPanel(
                        sessions: (try? TmuxSessionListing.parse(Data("infra|1|0\nwork|2|2\n".utf8))) ?? [],
                        loading: false, error: nil, reconnectTarget: "work", canSelect: true,
                        select: {
                            sessionSelection = "Selected " + $0.name
                            showSessions = false
                        },
                        refresh: {}, close: { showSessions = false }, terminalPicker: { showSessions = false })
                }
            }
            .overlay {
                if phase != .active {
                    Color.black.ignoresSafeArea().overlay(Text("Terminal hidden").foregroundStyle(.white))
                }
            }
            .onChange(of: phase) { _, next in
                model.terminal.isSurfaceVisible = next == .active
                model.gesturesEnabled = next == .active && !showComposer && !showSessions
            }
            .onChange(of: showComposer || showSessions) { _, presented in
                model.gesturesEnabled = !presented && phase == .active
            }
            .sheet(item: $model.selection) { snapshot in
                NavigationStack {
                    TerminalSelectionText(snapshot: snapshot)
                        .navigationTitle("Select terminal text")
                        .toolbar { Button("Done") { model.selection = nil } }
                }
            }
            .sheet(isPresented: $showComposer) {
                NavigationStack {
                    VStack {
                        Text("Synthetic harness: no remote command is executed.").font(.caption)
                        TextEditor(text: $model.draft).accessibilityLabel("Prompt draft")
                        Button("Paste to fixture") { model.terminal.paste(text: model.draft) }
                    }.padding().navigationTitle("Compose")
                        .toolbar { Button("Done") { showComposer = false } }
                }
            }
            .task { await model.runChecks() }
        }
    }

#endif

@MainActor
func safeTerminalConfiguration() -> TerminalConfiguration {
    TerminalConfiguration { builder in
        builder.withCustom("font-family", "JetBrains Mono")
        builder.withCustom("clipboard-read", "deny")
        builder.withCustom("clipboard-write", "deny")
        builder.withCustom("link-url", "false")
        builder.withCustom("scrollback-limit", "10000000")
    }
}

// A window-level cover also hides sheets; a terminal-view overlay alone does not.
@MainActor
private enum PrivacyCover {
    private static var covers: [UIWindow: UIView] = [:]
    static func hide(_ scene: UIWindowScene) {
        for window in scene.windows where covers[window] == nil {
            let cover = UIView(frame: window.bounds)
            cover.backgroundColor = .black
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cover.accessibilityLabel = "Content hidden"
            window.addSubview(cover)
            covers[window] = cover
        }
    }
    static func reveal(_ scene: UIWindowScene) {
        for window in scene.windows {
            covers.removeValue(forKey: window)?.removeFromSuperview()
        }
    }
}
