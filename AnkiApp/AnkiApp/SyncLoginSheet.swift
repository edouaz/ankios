// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

struct SyncLoginSheet: View {
    var syncStore: SyncStore

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var customServer = ""
    @State private var isLoggingIn = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("AnkiWeb Email", text: $username)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                Section {
                    TextField("http://192.168.1.10:8080/", text: $customServer)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Self-Hosted Server (Optional)")
                } footer: {
                    Text(
                        "Leave empty to sync with AnkiWeb (free account at ankiweb.net). "
                            + "Or run your own server — it's built into Anki: "
                            + "`anki --syncserver` on any desktop machine.")
                }
            }
            .onAppear { customServer = syncStore.customEndpoint ?? "" }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoggingIn {
                        ProgressView()
                    } else {
                        Button("Sign In") { Task { await login() } }
                            .disabled(username.isEmpty || password.isEmpty)
                    }
                }
            }
            .alert(
                "Couldn't Sign In",
                isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
            ) {
                Button("OK") { error = nil }
            } message: {
                Text(String(describing: error))
            }
        }
    }

    private func login() async {
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            let server = customServer.trimmingCharacters(in: .whitespaces)
            syncStore.customEndpoint = server.isEmpty ? nil : server
            try await syncStore.signIn(username: username, password: password)
            dismiss()
        } catch {
            self.error = error
        }
    }
}
