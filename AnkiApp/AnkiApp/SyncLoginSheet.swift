// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

struct SyncLoginSheet: View {
    let backend: Backend
    /// Called with the new hkey once login succeeds.
    let onLoggedIn: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
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
            }
            .navigationTitle("Sign In to AnkiWeb")
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
                "Couldn't Sign In", isPresented: .constant(error != nil),
                actions: {
                    Button("OK") { error = nil }
                },
                message: {
                    Text(String(describing: error))
                })
        }
    }

    private func login() async {
        isLoggingIn = true
        defer { isLoggingIn = false }
        do {
            let auth = try await backend.syncLogin(username: username, password: password)
            onLoggedIn(auth.hkey)
            dismiss()
        } catch {
            self.error = error
        }
    }
}
