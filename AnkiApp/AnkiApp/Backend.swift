// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Anki
import Foundation
import SwiftProtobuf
#if DEBUG
    import UIKit
#endif

/// Thin Swift wrapper over the C FFI in `rsbridge-ios` (`Anki.xcframework`).
/// FFI calls are blocking, so this is an actor: callers never touch the
/// backend from the main thread.
actor Backend {
    /// Service indices, looked up in
    /// `out/pylib/anki/_backend_generated.py` for the RPCs v1 needs.
    private enum Service: UInt32 {
        case sync = 1
        case collection = 3
        case decks = 7
        case scheduler = 13
        case cardRendering = 27
        case importExport = 39
        case stats = 43
        #if DEBUG
            // Only used by the test-data seeding below, not part of the
            // locked v1 RPC list.
            case notetypes = 23
            case notes = 25
        #endif
    }

    struct BackendCallError: Error {
        let message: String
        let kind: Anki_Backend_BackendError.Kind
    }

    struct OpenError: Error {}

    // Safe to touch unisolated from deinit: by then no other reference to
    // this actor exists, so there's no concurrent access to race with.
    private nonisolated(unsafe) let handle: OpaquePointer

    // Immutable after init, so safe to read synchronously (e.g. from the
    // media WKURLSchemeHandler, which runs off the actor).
    nonisolated let mediaFolderPath: String

    // async so this runs on the actor's executor, letting init call other
    // isolated methods (openCollection) synchronously below.
    init() async throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let ankiDir = appSupport.appendingPathComponent("anki", isDirectory: true)
        try FileManager.default.createDirectory(at: ankiDir, withIntermediateDirectories: true)

        let collectionPath = ankiDir.appendingPathComponent("collection.anki2").path
        // Mirrors pylib/anki/media.py:media_paths_from_col_path.
        let mediaFolderPath = ankiDir.appendingPathComponent("collection.media").path
        let mediaDbPath = mediaFolderPath + ".db2"
        try FileManager.default.createDirectory(
            atPath: mediaFolderPath, withIntermediateDirectories: true)

        var initMsg = Anki_Backend_BackendInit()
        initMsg.preferredLangs = [Locale.current.language.languageCode?.identifier ?? "en"]
        initMsg.server = false
        let initBytes = try initMsg.serializedData()

        guard
            let handle = initBytes.withUnsafeBytes({ raw -> OpaquePointer? in
                anki_open_backend(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
            })
        else {
            throw OpenError()
        }
        self.handle = handle
        self.mediaFolderPath = mediaFolderPath

        _ = try openCollection(
            collectionPath: collectionPath,
            mediaFolderPath: mediaFolderPath,
            mediaDbPath: mediaDbPath)
    }

    deinit {
        anki_close_backend(handle)
    }

    private func run(_ service: Service, _ method: UInt32, _ input: Data) throws -> Data {
        let (code, output): (Int32, AnkiByteBuf) = input.withUnsafeBytes { raw in
            var output = AnkiByteBuf()
            let code = anki_run_command(
                handle, service.rawValue, method,
                raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &output)
            return (code, output)
        }
        defer { anki_free_bytes(output) }
        let data = output.ptr.map { Data(bytes: $0, count: output.len) } ?? Data()
        if code != 0 {
            let err = try Anki_Backend_BackendError(serializedBytes: data)
            throw BackendCallError(message: err.message, kind: err.kind)
        }
        return data
    }

    // MARK: v1 RPCs

    private func openCollection(
        collectionPath: String, mediaFolderPath: String, mediaDbPath: String
    ) throws -> Anki_Generic_Empty {
        var req = Anki_Collection_OpenCollectionRequest()
        req.collectionPath = collectionPath
        req.mediaFolderPath = mediaFolderPath
        req.mediaDbPath = mediaDbPath
        return try Anki_Generic_Empty(
            serializedBytes: run(.collection, 0, req.serializedData()))
    }

    func getUndoStatus() throws -> Anki_Collection_UndoStatus {
        try Anki_Collection_UndoStatus(
            serializedBytes: run(.collection, 7, Data()))
    }

    func undo() throws -> Anki_Collection_OpChangesAfterUndo {
        try Anki_Collection_OpChangesAfterUndo(
            serializedBytes: run(.collection, 8, Data()))
    }

    func closeCollection(downgradeToSchema11: Bool = false) throws -> Anki_Generic_Empty {
        var req = Anki_Collection_CloseCollectionRequest()
        req.downgradeToSchema11 = downgradeToSchema11
        return try Anki_Generic_Empty(
            serializedBytes: run(.collection, 1, req.serializedData()))
    }

    func deckTree(now: Int64 = Int64(Date().timeIntervalSince1970)) throws -> Anki_Decks_DeckTreeNode
    {
        var req = Anki_Decks_DeckTreeRequest()
        req.now = now
        return try Anki_Decks_DeckTreeNode(
            serializedBytes: run(.decks, 4, req.serializedData()))
    }

    /// `get_queued_cards` scopes its queue to a single "current deck"
    /// (`decks::current.rs::get_current_deck`, defaulting to deck 1
    /// "Default" until this is called) — not the whole collection. Needed
    /// for "tap a deck → review its cards" to actually work; without it,
    /// every deck review silently reviews whatever deck 1 happens to be.
    func setCurrentDeck(deckID: Int64) throws -> Anki_Collection_OpChanges {
        var req = Anki_Decks_DeckId()
        req.did = deckID
        return try Anki_Collection_OpChanges(
            serializedBytes: run(.decks, 22, req.serializedData()))
    }

    func getQueuedCards(fetchLimit: UInt32 = 1, intradayLearningOnly: Bool = false) throws
        -> Anki_Scheduler_QueuedCards
    {
        var req = Anki_Scheduler_GetQueuedCardsRequest()
        req.fetchLimit = fetchLimit
        req.intradayLearningOnly = intradayLearningOnly
        return try Anki_Scheduler_QueuedCards(
            serializedBytes: run(.scheduler, 3, req.serializedData()))
    }

    func answerCard(_ answer: Anki_Scheduler_CardAnswer) throws -> Anki_Collection_OpChanges {
        try Anki_Collection_OpChanges(
            serializedBytes: run(.scheduler, 4, answer.serializedData()))
    }

    func describeNextStates(_ states: Anki_Scheduler_SchedulingStates) throws -> [String] {
        try Anki_Generic_StringList(
            serializedBytes: run(.scheduler, 24, states.serializedData())
        ).vals
    }

    func congratsInfo() throws -> Anki_Scheduler_CongratsInfoResponse {
        try Anki_Scheduler_CongratsInfoResponse(
            serializedBytes: run(.scheduler, 11, Data()))
    }

    func buryOrSuspendCards(
        cardIds: [Int64], mode: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode
    ) throws -> Anki_Collection_OpChangesWithCount {
        var req = Anki_Scheduler_BuryOrSuspendCardsRequest()
        req.cardIds = cardIds
        req.mode = mode
        return try Anki_Collection_OpChangesWithCount(
            serializedBytes: run(.scheduler, 14, req.serializedData()))
    }

    func renderExistingCard(
        cardId: Int64, browser: Bool = false, partialRender: Bool = false
    ) throws -> Anki_CardRendering_RenderCardResponse {
        var req = Anki_CardRendering_RenderExistingCardRequest()
        req.cardID = cardId
        req.browser = browser
        req.partialRender = partialRender
        return try Anki_CardRendering_RenderCardResponse(
            serializedBytes: run(.cardRendering, 6, req.serializedData()))
    }

    func extractAvTags(text: String, questionSide: Bool) throws
        -> Anki_CardRendering_ExtractAvTagsResponse
    {
        var req = Anki_CardRendering_ExtractAvTagsRequest()
        req.text = text
        req.questionSide = questionSide
        return try Anki_CardRendering_ExtractAvTagsResponse(
            serializedBytes: run(.cardRendering, 3, req.serializedData()))
    }

    /// Imports a `.apkg` deck package (notes, cards, decks, media) into the
    /// open collection. Options come from the backend's saved import presets
    /// — the same defaults the desktop import dialog starts from.
    func importAnkiPackage(packagePath: String) throws -> Anki_ImportExport_ImportResponse {
        let options = try Anki_ImportExport_ImportAnkiPackageOptions(
            serializedBytes: run(.importExport, 3, Data()))
        var req = Anki_ImportExport_ImportAnkiPackageRequest()
        req.packagePath = packagePath
        req.options = options
        return try Anki_ImportExport_ImportResponse(
            serializedBytes: run(.importExport, 2, req.serializedData()))
    }

    /// Aggregated stats for the Stats screen. `search: ""` = whole
    /// collection; `days` bounds the review-history range (the calendar
    /// heatmap keys `reviews.count` by day offset, 0 = today, negative = past).
    func graphs(search: String = "", days: UInt32 = 365) throws -> Anki_Stats_GraphsResponse {
        var req = Anki_Stats_GraphsRequest()
        req.search = search
        req.days = days
        return try Anki_Stats_GraphsResponse(
            serializedBytes: run(.stats, 2, req.serializedData()))
    }

    func syncLogin(username: String, password: String, endpoint: String? = nil) throws
        -> Anki_Sync_SyncAuth
    {
        var req = Anki_Sync_SyncLoginRequest()
        req.username = username
        req.password = password
        if let endpoint {
            req.endpoint = endpoint
        }
        return try Anki_Sync_SyncAuth(
            serializedBytes: run(.sync, 3, req.serializedData()))
    }

    func syncStatus(_ auth: Anki_Sync_SyncAuth) throws -> Anki_Sync_SyncStatusResponse {
        try Anki_Sync_SyncStatusResponse(
            serializedBytes: run(.sync, 4, auth.serializedData()))
    }

    func syncCollection(auth: Anki_Sync_SyncAuth, syncMedia: Bool) throws
        -> Anki_Sync_SyncCollectionResponse
    {
        var req = Anki_Sync_SyncCollectionRequest()
        req.auth = auth
        req.syncMedia = syncMedia
        return try Anki_Sync_SyncCollectionResponse(
            serializedBytes: run(.sync, 5, req.serializedData()))
    }

    func syncMedia(_ auth: Anki_Sync_SyncAuth) throws -> Anki_Generic_Empty {
        try Anki_Generic_Empty(
            serializedBytes: run(.sync, 0, auth.serializedData()))
    }

    /// `sync_collection` only negotiates: on a fresh local collection (or
    /// after a schema change) it reports `fullDownload`/`fullUpload`/
    /// `fullSync` as required without transferring anything, and this is
    /// the RPC that actually performs that transfer. Not in the roadmap's
    /// original v1 RPC list — added because the very first sync on a
    /// fresh install always hits this path (see Step 4 Sync notes).
    func fullUploadOrDownload(auth: Anki_Sync_SyncAuth, upload: Bool, serverUsn: Int32?) throws
        -> Anki_Generic_Empty
    {
        var req = Anki_Sync_FullUploadOrDownloadRequest()
        req.auth = auth
        req.upload = upload
        if let serverUsn {
            req.serverUsn = serverUsn
        }
        return try Anki_Generic_Empty(
            serializedBytes: run(.sync, 6, req.serializedData()))
    }

    #if DEBUG
        // MARK: Debug-only test data seeding
        //
        // Not part of the roadmap's locked v1 RPC list — a testing
        // convenience so Review/Media/Audio can be exercised on a fresh
        // collection without waiting on a real AnkiWeb sync. Never
        // compiled into a release build.

        /// Adds "Test Deck" with a couple of notes (one plain, one with an
        /// image and a [sound:...] tag) the first time it's called on a
        /// given collection. Safe to call on every launch.
        func seedTestDataIfNeeded() async throws {
            let tree = try await deckTree()
            if tree.children.contains(where: { $0.name == "Test Deck" }) {
                return
            }

            let notetypeID = try await getNotetypeIdByName("Basic")
            guard notetypeID != 0 else { return }

            var deck = try await newDeck()
            deck.name = "Test Deck"
            let deckID = try await addDeck(deck)

            try writeTestMedia()

            var note1 = try await newNote(notetypeID: notetypeID)
            note1.fields = ["Capital of France?", "Paris"]
            _ = try await addNote(note1, deckID: deckID)

            var note2 = try await newNote(notetypeID: notetypeID)
            note2.fields = [
                "<img src=\"anki-test-star.png\">What shape is this?",
                "A star [sound:anki-test-tone.wav]",
            ]
            _ = try await addNote(note2, deckID: deckID)
        }

        private func getNotetypeIdByName(_ name: String) throws -> Int64 {
            var req = Anki_Generic_String()
            req.val = name
            return try Anki_Notetypes_NotetypeId(
                serializedBytes: run(.notetypes, 10, req.serializedData())
            ).ntid
        }

        private func newDeck() throws -> Anki_Decks_Deck {
            try Anki_Decks_Deck(serializedBytes: run(.decks, 0, Data()))
        }

        private func addDeck(_ deck: Anki_Decks_Deck) throws -> Int64 {
            try Anki_Collection_OpChangesWithId(
                serializedBytes: run(.decks, 1, deck.serializedData())
            ).id
        }

        private func newNote(notetypeID: Int64) throws -> Anki_Notes_Note {
            var req = Anki_Notetypes_NotetypeId()
            req.ntid = notetypeID
            return try Anki_Notes_Note(
                serializedBytes: run(.notes, 0, req.serializedData()))
        }

        private func addNote(_ note: Anki_Notes_Note, deckID: Int64) throws
            -> Anki_Notes_AddNoteResponse
        {
            var req = Anki_Notes_AddNoteRequest()
            req.note = note
            req.deckID = deckID
            return try Anki_Notes_AddNoteResponse(
                serializedBytes: run(.notes, 1, req.serializedData()))
        }

        private func writeTestMedia() throws {
            let mediaDir = URL(fileURLWithPath: mediaFolderPath)
            if let image = UIImage(systemName: "star.fill")?
                .withTintColor(.systemYellow, renderingMode: .alwaysOriginal),
                let png = image.pngData()
            {
                try png.write(to: mediaDir.appendingPathComponent("anki-test-star.png"))
            }
            try Self.toneWav(frequency: 440, duration: 0.4)
                .write(to: mediaDir.appendingPathComponent("anki-test-tone.wav"))
        }

        private static func toneWav(frequency: Double, duration: Double) -> Data {
            let sampleRate = 44100.0
            let sampleCount = Int(sampleRate * duration)
            let samples = (0..<sampleCount).map { i -> Int16 in
                let t = Double(i) / sampleRate
                return Int16(sin(2.0 * .pi * frequency * t) * 0.3 * Double(Int16.max))
            }

            var data = Data()
            func append32(_ v: UInt32) {
                withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
            }
            func append16(_ v: UInt16) {
                withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
            }
            data.append(contentsOf: "RIFF".utf8)
            append32(UInt32(36 + samples.count * 2))
            data.append(contentsOf: "WAVE".utf8)
            data.append(contentsOf: "fmt ".utf8)
            append32(16)
            append16(1)  // PCM
            append16(1)  // mono
            append32(UInt32(sampleRate))
            append32(UInt32(sampleRate) * 2)  // byte rate
            append16(2)  // block align
            append16(16)  // bits per sample
            data.append(contentsOf: "data".utf8)
            append32(UInt32(samples.count * 2))
            for s in samples {
                append16(UInt16(bitPattern: s))
            }
            return data
        }
    #endif
}
