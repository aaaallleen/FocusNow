import AppKit
import FocusNowCore
import Observation

/// The menu bar item: a glyph plus the countdown in tabular digits.
@MainActor
final class StatusItemController: NSObject {
    private let engine: TimerEngine
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var onClick: (() -> Void)?
    var button: NSStatusBarButton? { item.button }

    init(engine: TimerEngine) {
        self.engine = engine
        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityLabel("FocusNow")
        observe()
    }

    @objc private func clicked() {
        onClick?()
    }

    /// Redraws now, and again whenever anything it read from the engine changes.
    private func observe() {
        withObservationTracking {
            redraw()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func redraw() {
        guard let button = item.button else { return }
        let status = engine.status
        let kind = engine.active?.kind ?? engine.nextKind

        let symbol: String, description: String
        switch status {
        case .paused: (symbol, description) = ("pause.fill", "Paused")
        case .running where kind.isBreak: (symbol, description) = ("cup.and.saucer.fill", "On a break")
        case .running: (symbol, description) = ("hourglass", "Focusing")
        case .idle: (symbol, description) = ("hourglass", "FocusNow")
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        image?.isTemplate = true
        button.image = image

        if status == .idle {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.contentTintColor = nil
        } else {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .baselineOffset: 0.5,
            ]
            let isBreak = kind.isBreak && status == .running
            if isBreak { attributes[.foregroundColor] = Theme.restNS }
            button.attributedTitle = NSAttributedString(
                string: " " + TimeFormat.clock(engine.remainingSeconds), attributes: attributes)
            button.imagePosition = .imageLeading
            button.contentTintColor = isBreak ? Theme.restNS : nil
        }
        button.appearsDisabled = status == .paused
    }
}
