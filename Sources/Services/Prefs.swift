import Foundation
import Carbon.HIToolbox

/// Central list of UserDefaults keys and defaults shared by `@AppStorage` views and the services.
enum Prefs {
    static let stripWidth = "stripWidth"
    static let revealDelay = "revealDelayMs"
    static let animationDuration = "animationDurationMs"
    static let hideOnFocusLoss = "hideOnFocusLoss"
    static let stashKeyCode = "stashKeyCode"
    static let stashModifiers = "stashModifiers"
    static let stashLabel = "stashLabel"
    static let unstashKeyCode = "unstashKeyCode"
    static let unstashModifiers = "unstashModifiers"
    static let unstashLabel = "unstashLabel"

    static let defaultModifiers = controlKey | optionKey

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            stripWidth: 6.0,
            revealDelay: 150.0,
            animationDuration: 200.0,
            hideOnFocusLoss: true,
            stashKeyCode: kVK_ANSI_S,
            stashModifiers: defaultModifiers,
            stashLabel: "⌃⌥S",
            unstashKeyCode: kVK_ANSI_U,
            unstashModifiers: defaultModifiers,
            unstashLabel: "⌃⌥U",
        ])
    }

    private static var d: UserDefaults { .standard }
    static var strip: CGFloat { CGFloat(min(20, max(2, d.double(forKey: stripWidth)))) }
    static var delaySeconds: Double { max(0, d.double(forKey: revealDelay)) / 1000 }
    static var animationSeconds: Double { max(0, d.double(forKey: animationDuration)) / 1000 }
    static var hidesOnFocusLoss: Bool { d.bool(forKey: hideOnFocusLoss) }
}
