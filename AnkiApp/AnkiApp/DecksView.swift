// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

private struct DeckRow: Identifiable {
    let id: Int64
    let name: String
    let level: Int
    let newCount: UInt32
    let learnCount: UInt32
    let reviewCount: UInt32
}

/// Flattens the deck tree (skipping the synthetic root) into an indented
/// list. Full nested collapsing is a v2 concern; v1 just shows everything.
private func flatten(_ node: Anki_Decks_DeckTreeNode, level: Int = 0) -> [DeckRow] {
    var rows: [DeckRow] = []
    if node.level > 0 {
        rows.append(
            DeckRow(
                id: node.deckID, name: node.name, level: level,
                newCount: node.newCount, learnCount: node.learnCount,
                reviewCount: node.reviewCount))
    }
    for child in node.children {
        rows.append(contentsOf: flatten(child, level: level + 1))
    }
    return rows
}

struct DecksView: View {
    let backend: Backend
    var syncStore: SyncStore

    @State private var rows: [DeckRow]?
    @State private var loadError: Error?
    @State private var reviewingDeckID: Int64?
    @State private var showingLoginSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let rows {
                    if rows.isEmpty {
                        ContentUnavailableView(
                            "No Decks", systemImage: "rectangle.stack",
                            description: Text("Sync to pull your decks from AnkiWeb."))
                    } else {
                        List(rows) { row in
                            Button {
                                Task {
                                    // get_queued_cards reviews whatever
                                    // deck is "current" — must select it
                                    // first, or every tap reviews deck 1.
                                    _ = try? await backend.setCurrentDeck(deckID: row.id)
                                    reviewingDeckID = row.id
                                }
                            } label: {
                                deckRowLabel(row)
                            }
                            .buttonStyle(.plain)
                        }
                        .refreshable { await syncOrReload() }
                    }
                } else if loadError != nil {
                    ContentUnavailableView(
                        "Couldn't Load Decks", systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Decks")
            .navigationDestination(item: $reviewingDeckID) { _ in
                ReviewView(backend: backend)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    syncIndicator
                }
            }
            .sheet(isPresented: $showingLoginSheet) {
                SyncLoginSheet(syncStore: syncStore)
            }
            .alert(
                "Sync Failed", isPresented: Binding(
                    get: { syncStore.lastError != nil }, set: { if !$0 { syncStore.lastError = nil } })
            ) {
                Button("OK") { syncStore.lastError = nil }
            } message: {
                Text(String(describing: syncStore.lastError))
            }
        }
        .task {
            #if DEBUG
                try? await backend.seedTestDataIfNeeded()
            #endif
            await reload()
            if syncStore.isSignedIn {
                await syncStore.sync()
                await reload()
            }
        }
    }

    @ViewBuilder
    private var syncIndicator: some View {
        if !syncStore.isSignedIn {
            Button {
                showingLoginSheet = true
            } label: {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
            }
        } else if syncStore.isSyncing {
            ProgressView()
        } else {
            Button {
                Task {
                    await syncStore.sync()
                    await reload()
                }
            } label: {
                Image(systemName: "checkmark.icloud")
            }
        }
    }

    @ViewBuilder
    private func deckRowLabel(_ row: DeckRow) -> some View {
        HStack {
            Text(row.name)
                .padding(.leading, CGFloat(row.level - 1) * 16)
            Spacer()
            if row.newCount > 0 {
                Text("\(row.newCount)").foregroundStyle(.blue)
            }
            if row.learnCount > 0 {
                Text("\(row.learnCount)").foregroundStyle(.orange)
            }
            if row.reviewCount > 0 {
                Text("\(row.reviewCount)").foregroundStyle(.green)
            }
        }
    }

    private func reload() async {
        do {
            let tree = try await backend.deckTree()
            rows = flatten(tree)
        } catch {
            loadError = error
        }
    }

    private func syncOrReload() async {
        if syncStore.isSignedIn {
            await syncStore.sync()
        }
        await reload()
    }
}
