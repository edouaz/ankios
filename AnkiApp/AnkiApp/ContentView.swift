// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Opens the (only) collection once at launch, then shows the tab bar.
struct ContentView: View {
    @State private var backend: Backend?
    @State private var syncStore: SyncStore?
    @State private var openError: Error?

    var body: some View {
        Group {
            if let backend, let syncStore {
                TabView {
                    DecksView(backend: backend, syncStore: syncStore)
                        .tabItem { Label("Decks", systemImage: "rectangle.stack") }
                    StatsView(backend: backend)
                        .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                    AccountView(syncStore: syncStore)
                        .tabItem { Label("Account", systemImage: "person.crop.circle") }
                    SettingsView(backend: backend)
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                }
            } else if let openError {
                ContentUnavailableView(
                    "Couldn't Open Collection",
                    systemImage: "exclamationmark.triangle",
                    description: Text(String(describing: openError)))
            } else {
                ProgressView()
            }
        }
        .task {
            // Unbuffered so console output isn't lost if the process is
            // killed rather than exiting cleanly (verification only).
            setvbuf(stdout, nil, _IONBF, 0)
            do {
                let b = try await Backend()
                backend = b
                syncStore = SyncStore(backend: b)
            } catch {
                openError = error
            }
        }
    }
}
