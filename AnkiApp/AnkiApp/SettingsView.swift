// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

// Change this to your own Ko-fi page (or any donation URL).
private let donationURL = URL(string: "https://ko-fi.com/YOUR_HANDLE")!

/// App preferences. Backed by `@AppStorage` (UserDefaults) so every value is
/// read on launch and persisted the moment it changes — no custom store.
struct SettingsView: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    // Minutes since midnight; DatePicker below adapts it to a time.
    @AppStorage("reminderMinutes") private var reminderMinutes = 9 * 60

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback") {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                }

                Section {
                    Toggle("Daily Reminder", isOn: $notificationsEnabled)
                    if notificationsEnabled {
                        DatePicker(
                            "Time", selection: reminderTime,
                            displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A daily notification nudging you to review. Needs notification permission.")
                }

                Section("Support") {
                    Link(destination: donationURL) {
                        Label("Support the Developer", systemImage: "heart.fill")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: notificationsEnabled) { _, on in
                Task {
                    let scheduled = await Notifications.update(
                        enabled: on, at: reminderComponents)
                    // Permission denied → don't leave the toggle stuck on.
                    if on && !scheduled { notificationsEnabled = false }
                }
            }
            .onChange(of: reminderMinutes) { _, _ in
                guard notificationsEnabled else { return }
                Task { await Notifications.update(enabled: true, at: reminderComponents) }
            }
        }
    }

    private var reminderComponents: DateComponents {
        DateComponents(hour: reminderMinutes / 60, minute: reminderMinutes % 60)
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60,
                second: 0, of: Date()) ?? Date()
        } set: { newDate in
            let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
            reminderMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
