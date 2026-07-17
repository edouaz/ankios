// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

/// A one-shot confetti burst shown when a deck's queue empties. Pure
/// SwiftUI — pieces fall from the top and fade out once. Non-interactive so
/// it never blocks the congrats screen's Undo button underneath.
struct CelebrationView: View {
    var hapticsEnabled: Bool

    @State private var fallen = false
    // Fixed set built once so positions/colors don't reshuffle on re-render.
    private let pieces = (0..<60).map { _ in ConfettiPiece() }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(piece.color)
                        .frame(width: 7, height: 11)
                        .rotationEffect(.degrees(fallen ? piece.spin : 0))
                        .position(
                            x: piece.startX * geo.size.width,
                            y: fallen ? geo.size.height + 40 : -40)
                        .opacity(fallen ? 0 : 1)
                        .animation(
                            .easeIn(duration: piece.duration).delay(piece.delay), value: fallen)
                }
            }
        }
        .allowsHitTesting(false)
        .sensoryFeedback(trigger: fallen) { _, new in
            hapticsEnabled && new ? .success : nil
        }
        .onAppear { fallen = true }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let startX = Double.random(in: 0.05...0.95)
    let duration = Double.random(in: 1.4...2.6)
    let delay = Double.random(in: 0...0.5)
    let spin = Double.random(in: 180...900)
    let color = [Color.red, .orange, .yellow, .green, .blue, .purple, .pink]
        .randomElement()!
}
