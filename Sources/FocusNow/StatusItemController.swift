import AppKit
import FocusNowCore
import Observation

/// The menu bar item: a glyph plus the countdown in tabular digits, the
/// popover it opens, and the flash while a finished countdown waits.
@MainActor
final class StatusItemController: NSObject {
    private let engine: TimerEngine
    /// The chosen colourway's colours, read each time the button is drawn.
    private let palette: () -> Palette
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var flashTimer: Timer?
    private var flashDimmed = false

    /// Whether a click anywhere else closes the popover: yes when a click opened
    /// it, no when a finished countdown did (until the owner uses it).
    private(set) var closesOnOutsideClick = false
    /// Watches for clicks and app switches outside the popover while it shows.
    private var outsideMonitors: [Any] = []
    private var appSwitchObserver: NSObjectProtocol?
    /// The close animation is still running (`isShown` stays true until it ends).
    private(set) var isClosing = false
    /// Clicked again while it was closing: show it once the close finishes.
    private var reopenWhenClosed = false

    var button: NSStatusBarButton? { item.button }
    var isPopoverShown: Bool { popover.isShown }
    var isFlashing: Bool { flashTimer != nil }
    var popoverWindowVisible: Bool { popover.contentViewController?.view.window?.isVisible ?? false }
    var popoverWindow: NSWindow? { popover.contentViewController?.view.window }

    /// Lets the popover take keystrokes (typing into the digits).
    func makePopoverKey() {
        popoverWindow?.makeKey()
    }

    init(engine: TimerEngine, palette: @escaping () -> Palette) {
        self.engine = engine
        self.palette = palette
        super.init()
        popover.animates = true
        // Closing is handled here rather than by `.transient`, which only closes
        // on outside clicks while the app is active, and macOS usually declines
        // to activate a menu bar app when another app is in use.
        popover.behavior = .applicationDefined
        popover.delegate = self
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.imagePosition = .imageLeading
        observe()
    }

    func setPopoverContent(_ controller: NSViewController) {
        popover.contentViewController = controller
    }

    /// Light, dark, or nil to follow the Mac. Without it the popover takes its
    /// look from the menu bar item, which always follows the menu bar.
    func setPopoverAppearance(_ appearance: NSAppearance?) {
        popover.appearance = appearance
    }

    /// Opened by a click: the app activates and the popover closes on a click outside.
    /// Opened by a finished countdown: the frontmost app keeps keyboard focus and
    /// the popover stays until the owner responds.
    func showPopover(fromClick: Bool) {
        guard let button = item.button else { return }
        closesOnOutsideClick = fromClick
        recoverFromAMissedClose()
        if isClosing {
            reopenWhenClosed = true
            return
        }
        if popover.isShown { return }
        if fromClick { NSApp.activate() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        watchOutside()
    }

    func closePopover() {
        reopenWhenClosed = false
        stopWatchingOutside()
        guard popover.isShown, !isClosing else { return }
        endEditing()
        popover.close()
    }

    /// Closing mid-edit commits what was typed, as clicking away from a field does.
    fileprivate func endEditing() {
        popoverWindow?.makeFirstResponder(nil)
    }

    /// The owner answered a finish in the window: the popover the finish opened
    /// has done its job (it doesn't close on an outside click by itself).
    func ownerRespondedElsewhere() {
        if !closesOnOutsideClick { closePopover() }
    }

    /// After the owner interacts with a popover opened by a finish, it behaves
    /// like a clicked one again.
    func popoverWasUsed() {
        closesOnOutsideClick = true
    }

    /// Should AppKit ever skip `popoverDidClose`, a popover that's gone mustn't
    /// leave every later click waiting for a close that never finishes.
    private func recoverFromAMissedClose() {
        if isClosing && !popover.isShown { isClosing = false }
    }

    @objc func clicked() {
        engine.acknowledge()
        recoverFromAMissedClose()
        if popover.isShown && !isClosing {
            closePopover()
        } else {
            showPopover(fromClick: true)
        }
    }

    // MARK: - Closing on outside clicks

    /// A click in another app, on the desktop or in the menu bar; a click in one
    /// of this app's windows other than the popover; another app coming forward
    /// (⌘-Tab); or Escape closes a popover that closes on outside clicks.
    private func watchOutside() {
        guard outsideMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.interactionOutside() }
        }) {
            outsideMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.popoverWindow,
                      !self.isMenuBarItemWindow(event.window) else { return }
                self.interactionOutside()
            }
            return event
        }) {
            outsideMonitors.append(local)
        }
        // `.applicationDefined` leaves Escape to the app. While typing into the
        // digits, Escape belongs to the field (it drops the edit).
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let isEscape = event.keyCode == 53
            let window = event.window
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, isEscape, let popover = self.popoverWindow, window === popover,
                      self.closesOnOutsideClick, !(popover.firstResponder is NSText) else { return false }
                self.closePopover()
                return true
            }
            return handled ? nil : event
        }) {
            outsideMonitors.append(escape)
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ownPID else { return }
            MainActor.assumeIsolated { self?.interactionOutside() }
        }
    }

    private func stopWatchingOutside() {
        outsideMonitors.forEach(NSEvent.removeMonitor)
        outsideMonitors.removeAll()
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
    }

    /// The item's own clicks toggle the popover through `clicked()`. With more
    /// than one display each menu bar shows the item, so any status bar window
    /// of this app counts as the item's.
    private func isMenuBarItemWindow(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === item.button?.window || window.level == .statusBar
    }

    private func interactionOutside() {
        if closesOnOutsideClick { closePopover() }
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

    func redraw() {
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
            let p = palette()
            let breakColor = NSColor.dynamic(light: p.breakLight, dark: p.breakDark)
            if isBreak { attributes[.foregroundColor] = breakColor }
            let seconds = waiting ? 0 : engine.remainingSeconds
            button.attributedTitle = NSAttributedString(string: " " + TimeFormat.clock(seconds), attributes: attributes)
            button.imagePosition = .imageLeading
            button.contentTintColor = isBreak ? breakColor : nil
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

extension StatusItemController: NSPopoverDelegate {
    /// However the popover closes, a half-typed length is committed first.
    func popoverWillClose(_ notification: Notification) {
        isClosing = true
        stopWatchingOutside()
        endEditing()
    }

    func popoverDidClose(_ notification: Notification) {
        isClosing = false
        if reopenWhenClosed {
            reopenWhenClosed = false
            showPopover(fromClick: closesOnOutsideClick)
        }
    }
}
