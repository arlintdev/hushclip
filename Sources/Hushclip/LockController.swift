import AppKit
import LocalAuthentication

/// Decides when history locks, and asks for Touch ID (or the login password) to unlock it.
///
/// - "Until screen lock or sleep": locks when the screen locks, the screensaver starts,
///   the display or Mac sleeps, or the user switches away.
/// - Timed (15 min to 12 h): locks after that long without using Hushclip.
/// - Hushclip always starts locked when the lock is on.
@MainActor
final class LockController {
    static let durations: [(minutes: Int, title: String)] = [
        (0, "Until the screen locks or Mac sleeps"),
        (15, "15 minutes"),
        (30, "30 minutes"),
        (60, "1 hour"),
        (360, "6 hours"),
        (720, "12 hours"),
    ]

    private let store: ClipStore
    /// Called just before history locks (to close the overlay).
    var willLock: () -> Void = {}
    private var lastActivity = Date()
    private var authenticating = false
    private var idleTimer: Timer?

    init(store: ClipStore) {
        self.store = store

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenLocked() }
            }
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenLocked() }
            }
        }

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    /// "Touch ID" on Macs that have it, otherwise what macOS will ask for instead.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        default: return "your Mac password"
        }
    }

    func noteActivity() {
        lastActivity = Date()
    }

    func lockNow() {
        guard Prefs.lockEnabled, !store.isLocked else { return }
        willLock()
        store.lock()
    }

    /// Runs `body` with history available, asking the user to authenticate first if it's locked.
    func whenUnlocked(_ body: @escaping () -> Void) {
        guard store.isLocked else {
            noteActivity()
            body()
            return
        }
        authenticate(reason: "unlock your clipboard history") { [weak self] success in
            guard let self, success else { return }
            self.store.unlock()
            self.noteActivity()
            body()
        }
    }

    /// Touch ID, Apple Watch, or the login password, whichever macOS offers.
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        guard !authenticating else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            NSLog("Hushclip: authentication unavailable: \(error?.localizedDescription ?? "unknown")")
            completion(false)
            return
        }
        authenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, _ in
            Task { @MainActor in
                self?.authenticating = false
                completion(success)
            }
        }
    }

    private func screenLocked() {
        guard Prefs.lockAfterMinutes == 0 else { return }
        lockNow()
    }

    private func checkIdle() {
        let minutes = Prefs.lockAfterMinutes
        guard minutes > 0, Date().timeIntervalSince(lastActivity) > Double(minutes) * 60 else { return }
        lockNow()
    }
}
