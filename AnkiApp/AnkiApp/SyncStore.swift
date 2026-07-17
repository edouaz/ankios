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
    private static let currentEndpointKey = "sync_current_endpoint"
    private static let customEndpointKey = "sync_custom_endpoint"

    var isSignedIn: Bool { hkey != nil }

    /// User-set self-hosted sync server URL (nil = AnkiWeb). Not a secret,
    /// so UserDefaults is fine.
    var customEndpoint: String? {
        didSet {
            UserDefaults.standard.set(customEndpoint, forKey: Self.customEndpointKey)
            // Server changed — any assigned host from the old one is stale.
            currentEndpoint = nil
        }
    }

    /// The host the server last redirected us to (AnkiWeb load-balances
    /// accounts onto numbered hosts via `new_endpoint`). Mirrors the
    /// desktop's `profiles.py: sync_endpoint()` — ignoring this was a real
    /// deviation from the official client.
    private var currentEndpoint: String? {
        didSet { UserDefaults.standard.set(currentEndpoint, forKey: Self.currentEndpointKey) }
    }

    private var endpoint: String? { currentEndpoint ?? customEndpoint }

    init(backend: Backend) {
        self.backend = backend
        hkey = Keychain.loadHkey()
        username = UserDefaults.standard.string(forKey: Self.usernameDefaultsKey)
        customEndpoint = UserDefaults.standard.string(forKey: Self.customEndpointKey)
        currentEndpoint = UserDefaults.standard.string(forKey: Self.currentEndpointKey)
    }

    func signIn(username: String, password: String) async throws {
        let auth = try await backend.syncLogin(
            username: username, password: password, endpoint: endpoint)
        Keychain.saveHkey(auth.hkey)
        UserDefaults.standard.set(username, forKey: Self.usernameDefaultsKey)
        hkey = auth.hkey
        self.username = username
        if auth.hasEndpoint, !auth.endpoint.isEmpty {
            currentEndpoint = auth.endpoint
        }
        await sync()
    }

    func signOut() {
        Keychain.deleteHkey()
        UserDefaults.standard.removeObject(forKey: Self.usernameDefaultsKey)
        hkey = nil
        username = nil
        lastStatus = nil
        currentEndpoint = nil
    }

    private func makeAuth(hkey: String) -> Anki_Sync_SyncAuth {
        var auth = Anki_Sync_SyncAuth()
        auth.hkey = hkey
        if let endpoint {
            auth.endpoint = endpoint
        }
        return auth
    }

    func sync() async {
        guard let hkey else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            var auth = makeAuth(hkey: hkey)
            let response = try await backend.syncCollection(auth: auth, syncMedia: true)
            if response.hasNewEndpoint, !response.newEndpoint.isEmpty {
                currentEndpoint = response.newEndpoint
                auth.endpoint = response.newEndpoint
            }
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
            let response = try await backend.syncStatus(makeAuth(hkey: hkey))
            if response.hasNewEndpoint, !response.newEndpoint.isEmpty {
                currentEndpoint = response.newEndpoint
            }
            lastStatus = response.required
        } catch {
            lastError = error
        }
    }
}
