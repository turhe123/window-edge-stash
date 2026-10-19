import AppKit

/// A click-through borderless panel that draws a subtle accent line on a screen edge while a strip is hovered.
final class EdgeHighlight {
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        view.layer?.cornerRadius = 1.5
        p.contentView = view
        return p
    }()

    /// Shows the line at the given rect in AX (top-left origin) coordinates.
    func show(axRect: CGRect) {
        let frame = AX.flip(axRect)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }
}
