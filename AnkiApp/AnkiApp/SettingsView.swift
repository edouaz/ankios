// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

// Change this to your own Ko-fi page (or any donation URL).
private let donationURL = URL(string: "https://ko-fi.com/YOUR_HANDLE")!

/// App preferences. Backed by `@AppStorage` (UserDefaults) so every value is
/// read on launch and persisted the moment it changes — no custom store.
struct SettingsView: View {
    let backend: Backend

    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    // Minutes since midnight; DatePicker below adapts it to a time.
    @AppStorage("reminderMinutes") private var reminderMinutes = 9 * 60

    @State private var newPerDay = 20
    @State private var reviewsPerDay = 200
    @State private var limitsLoaded = false
    @State private var savingLimits = false
    @State private var limitsMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if limitsLoaded {
                        Stepper(value: $newPerDay, in: 0...9999, step: 5) {
                            LabeledContent("New Cards/Day", value: "\(newPerDay)")
                        }
                        Stepper(value: $reviewsPerDay, in: 0...9999, step: 10) {
                            LabeledContent("Max Reviews/Day", value: "\(reviewsPerDay)")
                        }
                        if savingLimits {
                            ProgressView()
                        } else {
                            Button("Apply to All Decks") {
                                Task { await saveLimits() }
                            }
                        }
                    } else {
                        ProgressView()
                    }
                } header: {
                    Text("Daily Limits")
                } footer: {
                    Text(limitsMessage ?? "Applies to every deck preset in the collection.")
                }

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
            .task { await loadLimits() }
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

    /// Shows the default preset's limits (the one most decks use).
    private func loadLimits() async {
        guard !limitsLoaded else { return }
        guard let resp = try? await backend.getDeckConfigsForUpdate(deckID: 1) else { return }
        let config =
            resp.allConfig.first(where: { $0.config.id == 1 })?.config ?? resp.defaults
        newPerDay = Int(config.config.newPerDay)
        reviewsPerDay = Int(config.config.reviewsPerDay)
        limitsLoaded = true
    }

    /// Writes the limits into every preset. Fetches fresh state first and
    /// passes the collection-level flags (fsrs, etc.) back unchanged —
    /// UpdateDeckConfigs saves those too, so dropping them would reset them.
    private func saveLimits() async {
        savingLimits = true
        defer { savingLimits = false }
        do {
            let resp = try await backend.getDeckConfigsForUpdate(deckID: 1)
            var req = Anki_DeckConfig_UpdateDeckConfigsRequest()
            req.targetDeckID = 1
            req.configs = resp.allConfig.map {
                var config = $0.config
                config.config.newPerDay = UInt32(newPerDay)
                config.config.reviewsPerDay = UInt32(reviewsPerDay)
                return config
            }
            req.mode = .normal
            req.limits = resp.currentDeck.limits
            req.cardStateCustomizer = resp.cardStateCustomizer
            req.newCardsIgnoreReviewLimit = resp.newCardsIgnoreReviewLimit
            req.fsrs = resp.fsrs
            req.applyAllParentLimits = resp.applyAllParentLimits
            req.fsrsHealthCheck = resp.fsrsHealthCheck
            _ = try await backend.updateDeckConfigs(req)
            limitsMessage = "Saved."
        } catch {
            limitsMessage = "Couldn't save: \(error)"
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
