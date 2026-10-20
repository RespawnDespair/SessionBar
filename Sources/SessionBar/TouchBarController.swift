import AppKit

/// Owns the Control Strip item (a row of dots) and the expanded bar with one button per session.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate, NSScrubberDataSource,
    @preconcurrency NSScrubberFlowLayoutDelegate {
    var onSelect: ((DisplaySession) -> Void)?

    private let trayIdentifier = NSTouchBarItem.Identifier("local.sessionbar.tray")
    private let sessionsIdentifier = NSTouchBarItem.Identifier("local.sessionbar.sessions")
    private let closeIdentifier = NSTouchBarItem.Identifier("local.sessionbar.close")
    private let itemIdentifier = NSUserInterfaceItemIdentifier("local.sessionbar.session")
    private let expandedKey = "touchBarExpanded"

    private var sessions: [DisplaySession] = []
    private var touchBar: NSTouchBar?
    private var trayItem: NSCustomTouchBarItem?
    private var trayButton: NSButton?
    private weak var scrubber: NSScrubber?
    private var scrubberWidth: NSLayoutConstraint?
    private var isPresented = false
    private var isExpanded: Bool {
        get { UserDefaults.standard.object(forKey: expandedKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: expandedKey) }
    }

    func update(_ newSessions: [DisplaySession], openOnAttention: Bool) {
        let layoutChanged = newSessions.map { "\($0.record.id)|\($0.name)" } != sessions.map { "\($0.record.id)|\($0.name)" }
        let newAttention = newSessions.contains { session in
            session.display == .attention
                && sessions.first { $0.record.id == session.record.id }?.display != .attention
        }
        sessions = newSessions
        installTrayIfNeeded()

        if newAttention && openOnAttention { isExpanded = true }
        if sessions.isEmpty {
            if let touchBar, isPresented { SystemModalTouchBar.dismiss(touchBar) }
            isPresented = false
        } else if isExpanded && (!isPresented || newAttention) {
            present()
        }

        if layoutChanged {
            scrubber?.reloadData()
            updateScrubberWidth()
        }
        redraw(at: Date.timeIntervalSinceReferenceDate)
    }

    /// Called by the animation timer; repaints dots without rebuilding anything.
    func redraw(at t: TimeInterval) {
        trayButton?.image = Appearance.summaryImage(sessions.map(\.display), at: t, height: 22, dot: 9, maxDots: 6)
        guard let scrubber else { return }
        for index in sessions.indices {
            (scrubber.itemViewForItem(at: index) as? SessionItemView)?.needsDisplay = true
        }
    }

    func close() {
        if let touchBar { SystemModalTouchBar.dismiss(touchBar) }
        if let trayItem { ControlStripItem.remove(trayItem) }
    }

    // MARK: Presentation

    private func installTrayIfNeeded() {
        guard trayItem == nil else { return }
        let item = NSCustomTouchBarItem(identifier: trayIdentifier)
        let button = NSButton(image: NSImage(size: NSSize(width: 9, height: 22)), target: self, action: #selector(toggle))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("Claude sessies")
        item.view = button
        item.visibilityPriority = .high
        trayItem = item
        trayButton = button
        ControlStripItem.add(item)
    }

    private func present() {
        let bar = touchBar ?? makeTouchBar()
        touchBar = bar
        SystemModalTouchBar.present(bar, trayIdentifier: trayIdentifier)
        isPresented = true
    }

    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [sessionsIdentifier, .flexibleSpace, closeIdentifier]
        return bar
    }

    @objc private func toggle() {
        if isPresented, let touchBar {
            SystemModalTouchBar.minimize(touchBar)
            isPresented = false
            isExpanded = false
        } else {
            isExpanded = true
            if !sessions.isEmpty { present() }
        }
    }

    @objc private func collapse() {
        guard let touchBar else { return }
        SystemModalTouchBar.minimize(touchBar)
        isPresented = false
        isExpanded = false
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case sessionsIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = makeScrubber()
            return item
        case closeIdentifier:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Verberg")
                ?? NSImage(size: NSSize(width: 16, height: 16))
            let button = NSButton(image: image, target: self, action: #selector(collapse))
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            item.view = button
            return item
        default:
            return nil
        }
    }

    // MARK: Scrubber

    private func makeScrubber() -> NSScrubber {
        let scrubber = NSScrubber()
        scrubber.register(SessionItemView.self, forItemIdentifier: itemIdentifier)
        scrubber.mode = .free
        scrubber.selectionBackgroundStyle = nil
        scrubber.showsAdditionalContentIndicators = true
        let layout = NSScrubberFlowLayout()
        layout.itemSpacing = 6
        scrubber.scrubberLayout = layout
        scrubber.dataSource = self
        scrubber.delegate = self
        let width = scrubber.widthAnchor.constraint(equalToConstant: contentWidth())
        width.isActive = true
        scrubberWidth = width
        self.scrubber = scrubber
        return scrubber
    }

    private func updateScrubberWidth() {
        scrubberWidth?.constant = contentWidth()
    }

    private func contentWidth() -> CGFloat {
        let items = sessions.map { SessionItemView.width(for: $0.name) }
        let total = items.reduce(0, +) + CGFloat(max(items.count - 1, 0)) * 6
        return min(max(total, 40), 880)
    }

    func numberOfItems(for scrubber: NSScrubber) -> Int { sessions.count }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let view = scrubber.makeItem(withIdentifier: itemIdentifier, owner: nil) as? SessionItemView ?? SessionItemView()
        if sessions.indices.contains(index) { view.session = sessions[index] }
        view.sessionProvider = { [weak self] in
            guard let self, self.sessions.indices.contains(index) else { return nil }
            return self.sessions[index]
        }
        return view
    }

    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout, sizeForItemAt index: Int) -> NSSize {
        guard sessions.indices.contains(index) else { return NSSize(width: 40, height: 30) }
        return NSSize(width: SessionItemView.width(for: sessions[index].name), height: 30)
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
        scrubber.selectedIndex = -1
        guard sessions.indices.contains(index) else { return }
        onSelect?(sessions[index])
    }
}

/// One session on the Touch Bar: a status dot and the project name in small type.
final class SessionItemView: NSScrubberItemView {
    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let maxTextWidth: CGFloat = 110

    var session: DisplaySession?
    /// Reads the live session at this index so blinking follows state changes between reloads.
    var sessionProvider: (() -> DisplaySession?)?

    static func width(for name: String) -> CGFloat {
        let text = (name as NSString).size(withAttributes: [.font: font]).width
        return ceil(min(text, maxTextWidth)) + 30
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let session = sessionProvider?() ?? session else { return }
        let t = Date.timeIntervalSinceReferenceDate

        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6)
        (session.display == .attention
            ? Appearance.orange.withAlphaComponent(0.22)
            : NSColor(white: 1, alpha: 0.12)).setFill()
        background.fill()

        let dot: CGFloat = 8
        Appearance.drawDot(in: NSRect(x: 9, y: (bounds.height - dot) / 2, width: dot, height: dot),
                           display: session.display, at: t)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph
        ]
        let textHeight = (session.name as NSString).size(withAttributes: attributes).height
        let textRect = NSRect(x: 22, y: (bounds.height - textHeight) / 2,
                              width: bounds.width - 30, height: textHeight)
        (session.name as NSString).draw(in: textRect, withAttributes: attributes)
    }
}
