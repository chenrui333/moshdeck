import GhosttyTerminal
import UIKit

/// Touch controls only. Ghostty still owns key encoding and sticky-modifier state.
@MainActor
final class TerminalKeyboardAccessory: UIInputView {
    private weak var terminal: PlainTextTerminalView?
    private let control = UIButton(type: .system)

    init(terminal: PlainTextTerminalView) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48), inputViewStyle: .keyboard)
        autoresizingMask = [.flexibleWidth]
        let escape = button("Esc", label: "Escape") { [weak terminal] in
            guard let terminal, terminal.acceptsTerminalInput() else { return }
            terminal.sendKey(.escape)
        }
        let hide = button(nil, label: "Hide Keyboard", symbol: "keyboard.chevron.compact.down") { [weak terminal] in
            terminal?.resignFirstResponder()
        }
        control.setTitle("Ctrl", for: .normal)
        control.accessibilityLabel = "Control"
        control.accessibilityHint = "Tap to arm for one key. Double-tap to lock. Tap again to clear."
        control.addAction(
            UIAction { [weak terminal] _ in
                guard let terminal, terminal.acceptsTerminalInput() else { return }
                terminal.toggleStickyModifier(.ctrl)
            }, for: .touchUpInside)
        size(control)
        let keys = UIStackView(arrangedSubviews: [control])
        keys.axis = .horizontal
        keys.spacing = 0
        for (title, label, key) in [
            ("Tab", "Tab", TerminalKey.tab),
            ("↑", "Up Arrow", .arrowUp), ("↓", "Down Arrow", .arrowDown),
            ("←", "Left Arrow", .arrowLeft), ("→", "Right Arrow", .arrowRight),
        ] {
            keys.addArrangedSubview(
                button(title, label: label) { [weak terminal] in
                    guard let terminal, terminal.acceptsTerminalInput() else { return }
                    terminal.sendKey(key)
                })
        }
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = true
        scroll.addSubview(keys)
        keys.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            keys.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            keys.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            keys.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            keys.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        let row = UIStackView(arrangedSubviews: [escape, scroll, hide])
        row.axis = .horizontal
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            escape.widthAnchor.constraint(equalToConstant: 44),
            hide.widthAnchor.constraint(equalToConstant: 44),
        ])
        terminal.setStickyModifierChangeHandler { [weak self] in self?.refreshControl() }
        refreshControl()
    }

    required init?(coder: NSCoder) { nil }

    private func size(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    private func button(_ title: String?, label: String, symbol: String? = nil, action: @escaping @MainActor () -> Void)
        -> UIButton
    {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        if let symbol { button.setImage(UIImage(systemName: symbol), for: .normal) }
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        size(button)
        return button
    }

    private func refreshControl() {
        let activation = terminal?.stickyActivation(for: .ctrl) ?? .inactive
        control.isSelected = activation != .inactive
        control.backgroundColor = activation == .inactive ? .clear : .systemBlue.withAlphaComponent(0.2)
        control.layer.cornerRadius = 6
        control.setTitle(activation == .locked ? "Ctrl•" : "Ctrl", for: .normal)
        switch activation {
        case .inactive: control.accessibilityValue = "Off"
        case .armed: control.accessibilityValue = "Armed for next key"
        case .locked: control.accessibilityValue = "Locked on"
        }
    }
}
