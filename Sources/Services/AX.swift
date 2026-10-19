import AppKit
import ApplicationServices

/// Failure-tolerant wrappers around the Accessibility API plus AX ⇄ Cocoa coordinate conversion.
/// AX coordinates have their origin at the top-left of the primary display with Y growing downward.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt (only once per launch the system actually displays it).
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func focusedWindow() -> (element: AXUIElement, pid: pid_t)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (unsafeBitCast(value, to: AXUIElement.self), app.processIdentifier)
    }

    static func position(_ el: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard let v = axValue(el, kAXPositionAttribute), AXValueGetValue(v, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ el: AXUIElement) -> CGSize? {
        var size = CGSize.zero
        guard let v = axValue(el, kAXSizeAttribute), AXValueGetValue(v, .cgSize, &size) else { return nil }
        return size
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = position(el), let s = size(el) else { return nil }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    static func setPosition(_ el: AXUIElement, _ point: CGPoint) -> AXError {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
        return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
    }

    @discardableResult
    static func setSize(_ el: AXUIElement, _ size: CGSize) -> AXError {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
        return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
    }

    static func title(_ el: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &value)
        return (value as? String) ?? ""
    }

    static func isFullScreen(_ el: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(el, "AXFullScreen" as CFString, &value)
        return (value as? Bool) ?? false
    }

    /// False once the owning app quit or the window closed.
    static func isValid(_ el: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &value) != .invalidUIElement
    }

    static func raise(_ el: AXUIElement) {
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    private static func axValue(_ el: AXUIElement, _ attr: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    // MARK: Coordinates

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Flips a rect between Cocoa (bottom-left) and AX (top-left) space; the transform is its own inverse.
    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static var pointer: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
