// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// Milestone 2 placeholder (see ios/ROADMAP.md Step 3): no UI yet, just
/// opens an empty collection and prints the decoded deck tree to the
/// console, to prove the Rust backend is reachable end to end.
struct ContentView: View {
    var body: some View {
        Text("Anki")
            .task {
                // Unbuffered so console output isn't lost if the process is
                // killed rather than exiting cleanly (verification only).
                setvbuf(stdout, nil, _IONBF, 0)
                do {
                    let backend = try await Backend()
                    let tree = try await backend.deckTree()
                    print("deck_tree: \(tree)")
                } catch {
                    print("backend error: \(error)")
                }
            }
    }
}
