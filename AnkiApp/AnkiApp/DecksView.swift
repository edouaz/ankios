// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import UniformTypeIdentifiers

private struct DeckRow: Identifiable {
    let id: Int64
    let name: String
    // Full "Parent::Child" path — used to search the deck's cards for reset.
    let fullName: String
    let level: Int
    let newCount: UInt32
    let learnCount: UInt32
    let reviewCount: UInt32
}

/// Flattens the deck tree (skipping the synthetic root) into an indented
/// list. Full nested collapsing is a v2 concern; v1 just shows everything.
private func flatten(_ node: Anki_Decks_DeckTreeNode, level: Int = 0, prefix: String = "")
    -> [DeckRow]
{
    var rows: [DeckRow] = []
    var fullName = ""
    if node.level > 0 {
        fullName = prefix.isEmpty ? node.name : prefix + "::" + node.name
        rows.append(
            DeckRow(
                id: node.deckID, name: node.name, fullName: fullName, level: level,
                newCount: node.newCount, learnCount: node.learnCount,
                reviewCount: node.reviewCount))
    }
    let childPrefix = node.level > 0 ? fullName : prefix
    for child in node.children {
        rows.append(contentsOf: flatten(child, level: level + 1, prefix: childPrefix))
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
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var resettingDeck: DeckRow?
    @State private var actionError: String?

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
                            deckRow(row)
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
            .navigationDestination(item: $reviewingDeckID) { deckID in
                ReviewView(backend: backend, deckID: deckID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button {
                            showingImporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    syncIndicator
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                // .apkg has no system UTType; the dynamic one still lets
                // the picker open deck packages from Files/iCloud.
                allowedContentTypes: [UTType(filenameExtension: "apkg") ?? .data]
            ) { result in
                Task { await importPackage(result) }
            }
            .alert(
                "Import", isPresented: Binding(
                    get: { importResult != nil }, set: { if !$0 { importResult = nil } })
            ) {
                Button("OK") { importResult = nil }
            } message: {
                Text(importResult ?? "")
            }
            .alert(
                "Restart Deck?",
                isPresented: Binding(
                    get: { resettingDeck != nil }, set: { if !$0 { resettingDeck = nil } }),
                presenting: resettingDeck
            ) { deck in
                Button("Restart", role: .destructive) {
                    Task { await resetDeck(deck) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { deck in
                Text("Every card in “\(deck.name)” goes back to new and all study progress is lost.")
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { actionError != nil }, set: { if !$0 { actionError = nil } })
            ) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "")
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
    private func deckRow(_ row: DeckRow) -> some View {
        Button {
            // Navigate immediately — ReviewView selects the deck during its
            // own loading state. Awaiting setCurrentDeck here made taps feel
            // dead (nothing on screen until the RPC returned).
            reviewingDeckID = row.id
        } label: {
            deckRowLabel(row)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                resettingDeck = row
            } label: {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
            .tint(.orange)
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

    /// Forgets every card in the deck (and its subdecks) so the whole deck
    /// can be studied again from scratch.
    private func resetDeck(_ row: DeckRow) async {
        do {
            let ids = try await backend.searchCards("deck:\"\(row.fullName)\"")
            if !ids.isEmpty {
                _ = try await backend.scheduleCardsAsNew(cardIDs: ids)
            }
            await reload()
        } catch {
            actionError = String(describing: error)
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

    private func importPackage(_ result: Result<URL, Error>) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let url = try result.get()
            // The picked URL is outside our sandbox and only readable while
            // security-scoped access is held; the Rust side opens the path
            // itself later, so copy the file into tmp first.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.copyItem(at: url, to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }

            let log = try await backend.importAnkiPackage(packagePath: tmp.path).log
            importResult =
                "\(log.new.count) new, \(log.updated.count) updated, "
                + "\(log.duplicate.count) duplicates skipped."
            await reload()
        } catch let error as Backend.BackendCallError {
            importResult = "Import failed: \(error.message)"
        } catch {
            importResult = "Import failed: \(error.localizedDescription)"
        }
    }

    private func syncOrReload() async {
        if syncStore.isSignedIn {
            await syncStore.sync()
        }
        await reload()
    }
}
