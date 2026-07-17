// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

struct AccountView: View {
    var syncStore: SyncStore

    @State private var showingLoginSheet = false

    var body: some View {
        NavigationStack {
            Form {
                if syncStore.isSignedIn {
                    Section("Account") {
                        LabeledContent("AnkiWeb", value: syncStore.username ?? "Signed in")
                        Button("Sign Out", role: .destructive) { syncStore.signOut() }
                    }
                    Section {
                        LabeledContent("Status", value: statusText)
                        if syncStore.isSyncing {
                            HStack {
                                Text("Syncing…")
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            Button("Check for Updates") { Task { await syncStore.checkStatus() } }
                            Button("Sync Now") { Task { await syncStore.sync() } }
                        }
                    } header: {
                        Text("What's on AnkiWeb")
                    } footer: {
                        Text(
                            "Sync pulls your decks, cards, and media from AnkiWeb, and pushes any local changes back up."
                        )
                    }
                    if let error = syncStore.lastError {
                        Section("Last Error") {
                            Text(String(describing: error))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Text("Sign in to AnkiWeb to sync your decks, cards, and media.")
                        Button("Sign In") { showingLoginSheet = true }
                    }
                }
            }
            .navigationTitle("Account")
            .sheet(isPresented: $showingLoginSheet) {
                SyncLoginSheet(syncStore: syncStore)
            }
        }
    }

    private var statusText: String {
        switch syncStore.lastStatus {
        case nil:
            return "Unknown"
        case .noChanges:
            return "Up to date"
        case .normalSync:
            return "Changes ready to sync"
        case .fullSync:
            return "Full sync required"
        case .UNRECOGNIZED:
            return "Unknown"
        }
    }
}
