import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.Key.maxItems) private var maxItems = 500
    @AppStorage(Prefs.Key.sensitiveExpiryMinutes) private var expiryMinutes = 60
    @AppStorage(Prefs.Key.captureConcealed) private var captureConcealed = true
    @AppStorage(Prefs.Key.autoPaste) private var autoPaste = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var trusted = Paster.isTrusted

    let onClearHistory: () -> Void
    let onRevealData: () -> Void
    let onLimitsChanged: () -> Void

    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Open history") {
                    Text("⌘ ⇧ V")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                }
                Toggle("Paste into the active app after choosing", isOn: $autoPaste)
                if autoPaste && !trusted {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Needs Accessibility permission to press ⌘V for you.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant…") { Paster.openAccessibilitySettings() }
                    }
                }
            }

            Section("History") {
                Picker("Keep up to", selection: $maxItems) {
                    ForEach([100, 250, 500, 1000, 2500], id: \.self) { Text("\($0) items").tag($0) }
                }
                .onChange(of: maxItems) { onLimitsChanged() }
                HStack {
                    Button("Clear History…", action: onClearHistory)
                    Button("Show Data Folder", action: onRevealData)
                }
            }

            Section {
                Toggle("Record concealed items from password managers", isOn: $captureConcealed)
                Picker("Delete passwords, secrets & cards", selection: $expiryMinutes) {
                    Text("After 5 minutes").tag(5)
                    Text("After 15 minutes").tag(15)
                    Text("After 1 hour").tag(60)
                    Text("After 1 day").tag(1440)
                    Text("After 1 week").tag(10080)
                    Text("Never").tag(0)
                }
                .onChange(of: expiryMinutes) { onLimitsChanged() }
            } header: {
                Text("Privacy")
            } footer: {
                Text("History is encrypted at rest with AES-256-GCM. The key is generated on this Mac, stored in your login Keychain (this device only), and never leaves it. Pinned items are never auto-deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Clipster \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    Spacer()
                    Link("github.com/arlintdev/clipster", destination: URL(string: "https://github.com/arlintdev/clipster")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .onReceive(ticker) { _ in trusted = Paster.isTrusted }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }
}
