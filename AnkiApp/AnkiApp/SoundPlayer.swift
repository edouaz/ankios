// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import AVFoundation

/// Plays a card's `[sound:...]` tags back to back.
@MainActor
final class SoundPlayer: NSObject, AVAudioPlayerDelegate, ObservableObject {
    private var queue: [URL] = []
    private var player: AVAudioPlayer?

    func play(_ filenames: [String], mediaFolderPath: String) {
        queue = filenames.map { URL(fileURLWithPath: mediaFolderPath).appendingPathComponent($0) }
        playNext()
    }

    private func playNext() {
        guard !queue.isEmpty else {
            player = nil
            return
        }
        let url = queue.removeFirst()
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            playNext()
            return
        }
        self.player = player
        player.delegate = self
        player.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playNext() }
    }
}
