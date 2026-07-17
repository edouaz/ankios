// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import Foundation

/// Shared AnkiWeb sync state — the Decks toolbar indicator and the Account
/// tab both read/drive this, so it lives in one place instead of being
/// duplicated per screen.
@MainActor
@Observable
final class SyncStore {
    private let backend: Backend

    private(set) var hkey: String?
    private(set) var username: String?
    private(set) var isSyncing = false
    var lastError: Error?
    private(set) var lastStatus: Anki_Sync_SyncStatusResponse.Required?

    private static let usernameDefaultsKey = "ankiweb_username"

    var isSignedIn: Bool { hkey != nil }

    init(backend: Backend) {
        self.backend = backend
        hkey = Keychain.loadHkey()
        username = UserDefaults.standard.string(forKey: Self.usernameDefaultsKey)
    }

    func signIn(username: String, password: String) async throws {
        let auth = try await backend.syncLogin(username: username, password: password)
        Keychain.saveHkey(auth.hkey)
        UserDefaults.standard.set(username, forKey: Self.usernameDefaultsKey)
        hkey = auth.hkey
        self.username = username
        await sync()
    }

    func signOut() {
        Keychain.deleteHkey()
        UserDefaults.standard.removeObject(forKey: Self.usernameDefaultsKey)
        hkey = nil
        username = nil
        lastStatus = nil
    }

    func sync() async {
        guard let hkey else { return }
        isSyncing = true
        lastError = nil
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
            lastStatus = .noChanges
        } catch {
            lastError = error
        }
    }

    func checkStatus() async {
        guard let hkey else { return }
        lastError = nil
        do {
            var auth = Anki_Sync_SyncAuth()
            auth.hkey = hkey
            lastStatus = try await backend.syncStatus(auth).required
        } catch {
            lastError = error
        }
    }
}
