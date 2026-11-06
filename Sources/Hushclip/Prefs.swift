import Foundation

/// UserDefaults-backed settings. Keys are shared with `@AppStorage` in SettingsView.
enum Prefs {
    enum Key {
        static let maxItems = "maxItems"
        static let sensitiveExpiryMinutes = "sensitiveExpiryMinutes"
        static let captureConcealed = "captureConcealed"
        static let autoPaste = "autoPaste"
        static let askedAccessibility = "askedAccessibility"
        static let lockEnabled = "lockEnabled"
        static let lockAfterMinutes = "lockAfterMinutes"
    }

    static let defaults = UserDefaults.standard

    static func register() {
        defaults.register(defaults: [
            Key.maxItems: 500,
            Key.sensitiveExpiryMinutes: 60,
            Key.captureConcealed: true,
            Key.autoPaste: true,
            Key.askedAccessibility: false,
            Key.lockEnabled: false,
            Key.lockAfterMinutes: 0,
        ])
    }

    static var maxItems: Int { max(10, defaults.integer(forKey: Key.maxItems)) }
    static var sensitiveExpiryMinutes: Int { defaults.integer(forKey: Key.sensitiveExpiryMinutes) }
    static var captureConcealed: Bool { defaults.bool(forKey: Key.captureConcealed) }
    static var autoPaste: Bool { defaults.bool(forKey: Key.autoPaste) }
    /// Require Touch ID (or the login password) to open history.
    static var lockEnabled: Bool { defaults.bool(forKey: Key.lockEnabled) }
    /// 0 = stay unlocked until the screen locks or the Mac sleeps; otherwise minutes since last use.
    static var lockAfterMinutes: Int { defaults.integer(forKey: Key.lockAfterMinutes) }
    static var askedAccessibility: Bool {
        get { defaults.bool(forKey: Key.askedAccessibility) }
        set { defaults.set(newValue, forKey: Key.askedAccessibility) }
    }
}
