// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Opens the (only) collection once at launch, then shows the deck list.
struct ContentView: View {
    @State private var backend: Backend?
    @State private var openError: Error?

    var body: some View {
        Group {
            if let backend {
                DecksView(backend: backend)
            } else if let openError {
                ContentUnavailableView(
                    "Couldn't Open Collection",
                    systemImage: "exclamationmark.triangle",
                    description: Text(String(describing: openError)))
            } else {
                ProgressView()
            }
        }
        .task {
            // Unbuffered so console output isn't lost if the process is
            // killed rather than exiting cleanly (verification only).
            setvbuf(stdout, nil, _IONBF, 0)
            do {
                backend = try await Backend()
            } catch {
                openError = error
            }
        }
    }
}
