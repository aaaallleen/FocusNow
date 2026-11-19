import AppKit
import FocusNowCore
import Observation

/// The menu bar item: a glyph plus the countdown in tabular digits, the
/// popover it opens, and the flash while a finished countdown waits.
@MainActor
final class StatusItemController: NSObject {
    private let engine: TimerEngine
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var flashTimer: Timer?
    private var flashDimmed = false

    var button: NSStatusBarButton? { item.button }
    var isPopoverShown: Bool { popover.isShown }
    var popoverBehavior: NSPopover.Behavior { popover.behavior }
    var isFlashing: Bool { flashTimer != nil }
    var popoverWindowVisible: Bool { popover.contentViewController?.view.window?.isVisible ?? false }

    init(engine: TimerEngine) {
        self.engine = engine
        super.init()
        popover.animates = true
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.imagePosition = .imageLeading
        observe()
    }

    func setPopoverContent(_ controller: NSViewController) {
        popover.contentViewController = controller
    }

    /// Opened by a click: the app activates and the popover closes on a click outside.
    /// Opened by a finished countdown: the frontmost app keeps keyboard focus and
    /// the popover stays until the owner responds.
    func showPopover(fromClick: Bool) {
        guard let button = item.button else { return }
        popover.behavior = fromClick ? .transient : .applicationDefined
        if popover.isShown { return }
        if fromClick { NSApp.activate() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closePopover() {
        popover.close()
    }

    /// After the owner interacts with a popover opened by a finish, it behaves
    /// like a clicked one again.
    func popoverWasUsed() {
        popover.behavior = .transient
    }

    @objc func clicked() {
        engine.acknowledge()
        if popover.isShown {
            closePopover()
        } else {
            showPopover(fromClick: true)
        }
    }

    // MARK: - Drawing

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
        let waiting = status == .idle && engine.needsAttention

        let symbol: String, description: String
        switch status {
        case .paused: (symbol, description) = ("pause.fill", "Paused")
        case .running where kind.isBreak: (symbol, description) = ("cup.and.saucer.fill", "On a break")
        case .running: (symbol, description) = ("hourglass", "Focusing")
        case .idle: (symbol, description) = ("hourglass", waiting ? "Finished" : "FocusNow")
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        image?.isTemplate = true
        button.image = image

        if status == .idle && !waiting {
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
            let seconds = waiting ? 0 : engine.remainingSeconds
            button.attributedTitle = NSAttributedString(string: " " + TimeFormat.clock(seconds), attributes: attributes)
            button.imagePosition = .imageLeading
            button.contentTintColor = isBreak ? Theme.restNS : nil
        }
        button.appearsDisabled = status == .paused
        setFlashing(engine.needsAttention)
    }

    // MARK: - Flash

    /// Pulses the item's opacity between 1.0 and 0.35, 0.5 s each way.
    func setFlashing(_ on: Bool) {
        guard on != isFlashing else { return }
        if on {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.flashStep() }
            }
            RunLoop.main.add(timer, forMode: .common)
            flashTimer = timer
            flashStep()
        } else {
            flashTimer?.invalidate()
            flashTimer = nil
            flashDimmed = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                item.button?.animator().alphaValue = 1
            }
        }
    }

    private func flashStep() {
        flashDimmed.toggle()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            item.button?.animator().alphaValue = flashDimmed ? 0.35 : 1
        }
    }
}
