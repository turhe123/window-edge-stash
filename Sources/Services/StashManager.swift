import AppKit
import ApplicationServices

/// The screen edge a window is parked against. The top edge is excluded because macOS keeps title bars below the menu bar.
enum StashEdge { case left, right, bottom }

/// One stashed window: its AX element, owner, original frame and current presentation state.
final class StashedWindow: Identifiable {
    let id = UUID()
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let title: String
    let originalFrame: CGRect
    let edge: StashEdge
    let screen: CGRect          // full display frame, AX coordinates
    var hiddenOrigin = CGPoint.zero
    var revealedOrigin = CGPoint.zero
    var hitRect = CGRect.zero   // the visible strip the pointer must dwell on
    var isRevealed = false
    var dwellStart: TimeInterval?
    var animation: Timer?
    var previousApp: NSRunningApplication?

    init(element: AXUIElement, pid: pid_t, frame: CGRect, edge: StashEdge, screen: CGRect) {
        self.element = element
        self.pid = pid
        self.appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "App"
        let t = AX.title(element)
        self.title = t.isEmpty ? "Untitled" : t
        self.originalFrame = frame
        self.edge = edge
        self.screen = screen
    }

    var revealedFrame: CGRect { CGRect(origin: revealedOrigin, size: originalFrame.size) }
}

/// Owns the in-memory stash list: stashes/unstashes windows, tracks the pointer against strips,
/// animates reveals and hides, and reacts to app, display and Space changes.
final class StashManager: ObservableObject {
    static let shared = StashManager()

    @Published private(set) var items: [StashedWindow] = []
    @Published private(set) var isTrusted = AX.isTrusted

    private static let stackStep: CGFloat = 44
    private static let leaveMargin: CGFloat = 10
    private let highlight = EdgeHighlight()
    private var pollTimer: Timer?
    private var mouseMonitor: Any?
    private var tickCount = 0
    private var pausedUntil: TimeInterval = 0
    private var lastStrip = Prefs.strip
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Lifecycle

    func start() {
        if !isTrusted { AX.requestTrust() }
        registerHotKeys()

        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.evaluatePointer()
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pauseForSpaceChange()
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.appActivated(app?.processIdentifier)
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.items.filter { $0.pid == app.processIdentifier }.forEach { self?.drop($0) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.unstashAll(animated: false)
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.stripSettingMayHaveChanged()
        }
    }

    func registerHotKeys() {
        let d = UserDefaults.standard
        HotKeyCenter.shared.register(id: 1, keyCode: d.integer(forKey: Prefs.stashKeyCode),
                                     modifiers: d.integer(forKey: Prefs.stashModifiers)) { [weak self] in self?.stashFocused() }
        HotKeyCenter.shared.register(id: 2, keyCode: d.integer(forKey: Prefs.unstashKeyCode),
                                     modifiers: d.integer(forKey: Prefs.unstashModifiers)) { [weak self] in self?.unstashFocusedOrLast() }
    }

    func requestAccess() {
        if !AX.requestTrust(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshTrust()
    }

    @discardableResult
    func refreshTrust() -> Bool {
        let trusted = AX.isTrusted
        if trusted != isTrusted { isTrusted = trusted }
        return trusted
    }

    // MARK: Stash / unstash

    func stashFocused() {
        guard refreshTrust() else { requestAccess(); return }
        guard let (element, pid) = AX.focusedWindow(), pid != getpid(),
              !AX.isFullScreen(element), let frame = AX.frame(element) else { NSSound.beep(); return }
        if let existing = items.first(where: { CFEqual($0.element, element) }) {
            if existing.isRevealed { hide(existing) }
            return
        }
        guard let (screen, edge) = chooseEdge(for: frame) else { NSSound.beep(); return }
        items.append(StashedWindow(element: element, pid: pid, frame: frame, edge: edge, screen: screen))
        layout(edge: edge, screen: screen)
    }

    func unstashFocusedOrLast() {
        let focused = AX.focusedWindow()?.element
        let target = items.first { focused != nil && CFEqual($0.element, focused) }
            ?? items.last { $0.isRevealed } ?? items.last
        if let target { unstash(target) } else { NSSound.beep() }
    }

    func unstash(_ item: StashedWindow, animated: Bool = true) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        item.animation?.invalidate()
        let restoreSize = { AX.setSize(item.element, item.originalFrame.size) }
        if animated {
            animate(item, to: item.originalFrame.origin) { restoreSize() }
        } else {
            AX.setPosition(item.element, item.originalFrame.origin)
            restoreSize()
        }
        layout(edge: item.edge, screen: item.screen)
    }

    func unstashAll(animated: Bool = true) {
        items.forEach { unstash($0, animated: animated) }
        highlight.hide()
    }

    /// Removes a window whose element became invalid (closed window or quit app) without touching it.
    private func drop(_ item: StashedWindow) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        item.animation?.invalidate()
        items.remove(at: index)
        layout(edge: item.edge, screen: item.screen)
    }

    // MARK: Geometry

    /// Picks the display containing most of the window and its nearest edge that doesn't border another display.
    private func chooseEdge(for frame: CGRect) -> (CGRect, StashEdge)? {
        let screens = NSScreen.screens.map { AX.flip($0.frame) }
        guard let screen = screens.max(by: { area($0.intersection(frame)) < area($1.intersection(frame)) }) else { return nil }
        let others = screens.filter { $0 != screen }
        let probes: [(StashEdge, CGRect, CGFloat)] = [
            (.left, CGRect(x: screen.minX - 2, y: screen.minY, width: 2, height: screen.height), frame.minX - screen.minX),
            (.right, CGRect(x: screen.maxX, y: screen.minY, width: 2, height: screen.height), screen.maxX - frame.maxX),
            (.bottom, CGRect(x: screen.minX, y: screen.maxY, width: screen.width, height: 2), screen.maxY - frame.maxY),
        ]
        let free = probes.filter { probe in !others.contains { $0.intersects(probe.1) } }
        guard let best = free.min(by: { $0.2 < $1.2 }) else { return nil }
        return (screen, best.0)
    }

    private func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

    private func visibleFrame(for screen: CGRect) -> CGRect {
        NSScreen.screens.first { AX.flip($0.frame) == screen }.map { AX.flip($0.visibleFrame) } ?? screen
    }

    /// Recomputes stacked targets for every window on one edge and slides hidden ones into place.
    private func layout(edge: StashEdge, screen: CGRect) {
        let group = items.filter { $0.edge == edge && $0.screen == screen }
        let strip = Prefs.strip
        let vis = visibleFrame(for: screen)
        for (i, item) in group.enumerated() {
            let size = item.originalFrame.size
            let offset = CGFloat(i) * Self.stackStep
            switch edge {
            case .left, .right:
                let y = min(vis.minY + offset, max(vis.minY, vis.maxY - Self.stackStep))
                let hiddenX = edge == .left ? screen.minX + strip - size.width : screen.maxX - strip
                let shownX = edge == .left ? vis.minX : vis.maxX - size.width
                item.hiddenOrigin = CGPoint(x: hiddenX, y: y)
                item.revealedOrigin = CGPoint(x: shownX, y: y)
            case .bottom:
                let x = min(vis.minX + offset, max(vis.minX, vis.maxX - Self.stackStep))
                item.hiddenOrigin = CGPoint(x: x, y: screen.maxY - strip)
                item.revealedOrigin = CGPoint(x: x, y: vis.maxY - size.height)
            }
            if !item.isRevealed {
                animate(item, to: item.hiddenOrigin) { [weak self] in self?.settleHidden(item, group: group) }
            }
        }
        updateHitRects(group)
    }

    /// Fallback for windows the system clamps on screen: retry once, then accept the real position as the stash spot.
    private func settleHidden(_ item: StashedWindow, group: [StashedWindow]) {
        guard let actual = AX.position(item.element) else { return }
        if hypot(actual.x - item.hiddenOrigin.x, actual.y - item.hiddenOrigin.y) > 2 {
            AX.setPosition(item.element, item.hiddenOrigin)
            if let retry = AX.position(item.element) { item.hiddenOrigin = retry }
        }
        updateHitRects(group)
    }

    /// Each strip is the window's on-screen sliver, cut where the next stacked window begins.
    private func updateHitRects(_ group: [StashedWindow]) {
        for (i, item) in group.enumerated() {
            var r = CGRect(origin: item.hiddenOrigin, size: item.originalFrame.size).intersection(item.screen)
            if r.isNull { r = .zero }
            let next = i + 1 < group.count ? group[i + 1].hiddenOrigin : nil
            switch item.edge {
            case .left:
                r = CGRect(x: item.screen.minX - 1, y: r.minY, width: max(r.maxX - item.screen.minX, 2) + 1,
                           height: next.map { max(0, $0.y - r.minY) } ?? r.height)
            case .right:
                r = CGRect(x: min(r.minX, item.screen.maxX - 2), y: r.minY, width: item.screen.maxX - r.minX + 1,
                           height: next.map { max(0, $0.y - r.minY) } ?? r.height)
            case .bottom:
                r = CGRect(x: r.minX, y: min(r.minY, item.screen.maxY - 2), width: next.map { max(0, $0.x - r.minX) } ?? r.width,
                           height: item.screen.maxY - r.minY + 1)
            }
            item.hitRect = r
        }
    }

    private func highlightRect(for item: StashedWindow) -> CGRect {
        let r = item.hitRect, s = item.screen, t: CGFloat = 3
        switch item.edge {
        case .left: return CGRect(x: s.minX, y: r.minY, width: t, height: r.height)
        case .right: return CGRect(x: s.maxX - t, y: r.minY, width: t, height: r.height)
        case .bottom: return CGRect(x: r.minX, y: s.maxY - t, width: r.width, height: t)
        }
    }

    private func stripSettingMayHaveChanged() {
        let strip = Prefs.strip
        guard strip != lastStrip else { return }
        lastStrip = strip
        var groups: [StashedWindow] = []
        for item in items where !groups.contains(where: { $0.edge == item.edge && $0.screen == item.screen }) {
            groups.append(item)
        }
        groups.forEach { layout(edge: $0.edge, screen: $0.screen) }
    }

    // MARK: Pointer tracking

    private func tick() {
        tickCount += 1
        if tickCount % 30 == 0 {
            refreshTrust()
            items.filter { !AX.isValid($0.element) }.forEach(drop)
        }
        evaluatePointer()
    }

    private func evaluatePointer() {
        guard !items.isEmpty, now >= pausedUntil else { highlight.hide(); return }
        let p = AX.pointer
        var hovered: StashedWindow?
        for item in items {
            if item.isRevealed {
                let keep = item.revealedFrame.union(item.hitRect).insetBy(dx: -Self.leaveMargin, dy: -Self.leaveMargin)
                if !keep.contains(p) { hide(item) }
            } else if item.hitRect.contains(p) {
                hovered = item
                if let start = item.dwellStart {
                    if now - start >= Prefs.delaySeconds { reveal(item) }
                } else {
                    item.dwellStart = now
                }
            } else {
                item.dwellStart = nil
            }
        }
        if let hovered, !hovered.isRevealed { highlight.show(axRect: highlightRect(for: hovered)) } else { highlight.hide() }
    }

    private func reveal(_ item: StashedWindow) {
        item.isRevealed = true
        item.dwellStart = nil
        let front = NSWorkspace.shared.frontmostApplication
        item.previousApp = front?.processIdentifier == item.pid ? nil : front
        AX.raise(item.element)
        NSRunningApplication(processIdentifier: item.pid)?.activate(options: [])
        animate(item, to: item.revealedOrigin)
    }

    private func hide(_ item: StashedWindow) {
        guard item.isRevealed else { return }
        item.isRevealed = false
        item.dwellStart = nil
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == item.pid {
            item.previousApp?.activate(options: [])
        }
        item.previousApp = nil
        animate(item, to: item.hiddenOrigin)
    }

    private func appActivated(_ pid: pid_t?) {
        guard Prefs.hidesOnFocusLoss else { return }
        items.filter { $0.isRevealed && $0.pid != pid }.forEach { item in
            item.previousApp = nil
            hide(item)
        }
    }

    private func pauseForSpaceChange() {
        pausedUntil = now + 0.8
        items.forEach { $0.dwellStart = nil }
        highlight.hide()
    }

    // MARK: Animation

    /// Steps the AX position along an ease-out cubic curve at ~60 Hz.
    private func animate(_ item: StashedWindow, to target: CGPoint, completion: (() -> Void)? = nil) {
        item.animation?.invalidate()
        item.animation = nil
        let duration = Prefs.animationSeconds
        guard let start = AX.position(item.element), duration > 0.01 else {
            if AX.setPosition(item.element, target) == .invalidUIElement { drop(item); return }
            completion?()
            return
        }
        let t0 = now
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (self.now - t0) / duration)
            let eased = 1 - pow(1 - progress, 3)
            let point = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            if AX.setPosition(item.element, point) == .invalidUIElement {
                timer.invalidate()
                self.drop(item)
            } else if progress >= 1 {
                timer.invalidate()
                item.animation = nil
                completion?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        item.animation = timer
    }
}
