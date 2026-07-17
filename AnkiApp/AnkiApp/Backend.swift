// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Anki
import Foundation
import SwiftProtobuf

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

    func syncLogin(username: String, password: String) throws -> Anki_Sync_SyncAuth {
        var req = Anki_Sync_SyncLoginRequest()
        req.username = username
        req.password = password
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
}
