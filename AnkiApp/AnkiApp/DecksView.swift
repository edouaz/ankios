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

    @State private var rows: [DeckRow]?
    @State private var loadError: Error?
    @State private var reviewingDeckID: Int64?
    @State private var hkey: String? = Keychain.loadHkey()
    @State private var isSyncing = false
    @State private var syncError: Error?
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
                SyncLoginSheet(backend: backend) { newHkey in
                    Keychain.saveHkey(newHkey)
                    hkey = newHkey
                    Task { await sync() }
                }
            }
            .alert(
                "Sync Failed", isPresented: Binding(
                    get: { syncError != nil }, set: { if !$0 { syncError = nil } })
            ) {
                Button("OK") { syncError = nil }
            } message: {
                Text(String(describing: syncError))
            }
        }
        .task {
            #if DEBUG
                try? await backend.seedTestDataIfNeeded()
            #endif
            await reload()
            if hkey != nil {
                await sync()
            }
        }
    }

    @ViewBuilder
    private var syncIndicator: some View {
        if hkey == nil {
            Button {
                showingLoginSheet = true
            } label: {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
            }
        } else if isSyncing {
            ProgressView()
        } else {
            Button {
                Task { await sync() }
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
        if hkey != nil {
            await sync()
        } else {
            await reload()
        }
    }

    private func sync() async {
        guard let hkey else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var auth = Anki_Sync_SyncAuth()
            auth.hkey = hkey
            let response = try await backend.syncCollection(auth: auth, syncMedia: true)
            switch response.required {
            case .fullDownload:
                // Fresh local collection, existing AnkiWeb data: the only
                // sane default for v1 (no destructive-choice UI yet).
                _ = try await backend.fullUploadOrDownload(
                    auth: auth, upload: false, serverUsn: response.serverMediaUsn)
            case .fullUpload:
                _ = try await backend.fullUploadOrDownload(
                    auth: auth, upload: true, serverUsn: response.serverMediaUsn)
            case .fullSync:
                // Ambiguous (schema changed on both sides) — default to
                // download. A real conflict picker is a v2 concern.
                _ = try await backend.fullUploadOrDownload(
                    auth: auth, upload: false, serverUsn: response.serverMediaUsn)
            case .noChanges, .normalSync, .UNRECOGNIZED:
                // sync_collection already performed the differential sync
                // and kicked off media sync in the background; this just
                // makes sure media sync started (harmless no-op if so).
                _ = try await backend.syncMedia(auth)
            }
            await reload()
        } catch {
            syncError = error
        }
    }
}
