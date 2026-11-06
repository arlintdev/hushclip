import Foundation

/// UserDefaults-backed settings. Keys are shared with `@AppStorage` in SettingsView.
enum Prefs {
    enum Key {
        static let maxItems = "maxItems"
        static let sensitiveExpiryMinutes = "sensitiveExpiryMinutes"
        static let captureConcealed = "captureConcealed"
        static let autoPaste = "autoPaste"
        static let askedAccessibility = "askedAccessibility"
    }

    static let defaults = UserDefaults.standard

    static func register() {
        defaults.register(defaults: [
            Key.maxItems: 500,
            Key.sensitiveExpiryMinutes: 60,
            Key.captureConcealed: true,
            Key.autoPaste: true,
            Key.askedAccessibility: false,
        ])
    }

    static var maxItems: Int { max(10, defaults.integer(forKey: Key.maxItems)) }
    static var sensitiveExpiryMinutes: Int { defaults.integer(forKey: Key.sensitiveExpiryMinutes) }
    static var captureConcealed: Bool { defaults.bool(forKey: Key.captureConcealed) }
    static var autoPaste: Bool { defaults.bool(forKey: Key.autoPaste) }
    static var askedAccessibility: Bool {
        get { defaults.bool(forKey: Key.askedAccessibility) }
        set { defaults.set(newValue, forKey: Key.askedAccessibility) }
    }
}
