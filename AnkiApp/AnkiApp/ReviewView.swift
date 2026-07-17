// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import AVFoundation
import SwiftUI

private func concat(_ nodes: [Anki_CardRendering_RenderedTemplateNode]) -> String {
    nodes.map { node -> String in
        switch node.value {
        case .text(let s): return s
        case .replacement(let r): return r.currentText
        case nil: return ""
        }
    }.joined()
}

struct ReviewView: View {
    let backend: Backend

    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var queue: Anki_Scheduler_QueuedCards?
    @State private var rendered: Anki_CardRendering_RenderCardResponse?
    @State private var showingAnswer = false
    @State private var nextStates: [String] = []
    @State private var loadError: Error?
    @State private var startedAt = Date()
    @State private var mediaSchemeHandler: MediaSchemeHandler?
    @State private var answeredCount = 0
    @State private var undoLabel = ""
    @State private var congrats: Anki_Scheduler_CongratsInfoResponse?
    @StateObject private var soundPlayer = SoundPlayer()

    var body: some View {
        Group {
            if let queue, let card = queue.cards.first, let rendered, let mediaSchemeHandler {
                VStack(spacing: 0) {
                    CardWebView(
                        html: showingAnswer ? concat(rendered.answerNodes) : concat(rendered.questionNodes),
                        css: rendered.css, mediaSchemeHandler: mediaSchemeHandler)
                    answerBar(card: card)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            Task { await undoTapped() }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .disabled(undoLabel.isEmpty)
                        Button {
                            replayAudio(rendered: rendered)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        Menu {
                            Button {
                                Task { await buryOrSuspend(.buryUser, card: card) }
                            } label: {
                                Label("Bury Card", systemImage: "moon.zzz")
                            }
                            Button(role: .destructive) {
                                Task { await buryOrSuspend(.suspend, card: card) }
                            } label: {
                                Label("Suspend Card", systemImage: "pause.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .navigationTitle("\(queue.newCount + queue.learningCount + queue.reviewCount) left")
                .navigationBarTitleDisplayMode(.inline)
            } else if loadError != nil {
                ContentUnavailableView(
                    "Couldn't Load Card", systemImage: "exclamationmark.triangle",
                    description: Text(String(describing: loadError!)))
            } else if queue != nil {
                ContentUnavailableView {
                    Label("All Done", systemImage: "checkmark.circle")
                } description: {
                    Text(congratsDescription)
                } actions: {
                    if !undoLabel.isEmpty {
                        Button("Undo \(undoLabel)") {
                            Task { await undoTapped() }
                        }
                    }
                }
                .overlay { CelebrationView(hapticsEnabled: hapticsEnabled) }
            } else {
                ProgressView()
            }
        }
        // nil suppresses the haptic entirely when the user turns it off.
        .sensoryFeedback(trigger: answeredCount) { _, _ in hapticsEnabled ? .success : nil }
        .task {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            mediaSchemeHandler = MediaSchemeHandler(mediaFolderPath: backend.mediaFolderPath)
            await loadNextCard()
        }
    }

    @ViewBuilder
    private func answerBar(card: Anki_Scheduler_QueuedCards.QueuedCard) -> some View {
        GlassEffectContainer(spacing: 8) {
            if showingAnswer {
                HStack(spacing: 8) {
                    ratingButton("Again", subtitle: nextStates[safe: 0], color: .red) {
                        Task { await answer(.again, card: card) }
                    }
                    ratingButton("Hard", subtitle: nextStates[safe: 1], color: .orange) {
                        Task { await answer(.hard, card: card) }
                    }
                    ratingButton("Good", subtitle: nextStates[safe: 2], color: .green) {
                        Task { await answer(.good, card: card) }
                    }
                    ratingButton("Easy", subtitle: nextStates[safe: 3], color: .blue) {
                        Task { await answer(.easy, card: card) }
                    }
                }
            } else {
                Button {
                    Task { await showAnswer(card: card) }
                } label: {
                    Text("Show Answer")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
            }
        }
        .padding()
    }

    @ViewBuilder
    private func ratingButton(
        _ title: String, subtitle: String?, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.subheadline.bold())
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .tint(color)
        .glassEffect(.regular.tint(color.opacity(0.3)).interactive(), in: .rect(cornerRadius: 16))
    }

    private var congratsDescription: String {
        guard let congrats else { return "No cards due right now." }
        var parts: [String] = []
        if congrats.learnRemaining > 0 {
            let mins = max(1, Int(congrats.secsUntilNextLearn) / 60)
            parts.append("Next learning card ready in \(mins) min.")
        } else {
            parts.append("No cards due right now.")
        }
        if congrats.haveUserBuried || congrats.haveSchedBuried {
            parts.append("Some cards were buried — they'll be back tomorrow.")
        }
        return parts.joined(separator: " ")
    }

    private func loadNextCard() async {
        showingAnswer = false
        nextStates = []
        undoLabel = (try? await backend.getUndoStatus().undo) ?? ""
        do {
            let q = try await backend.getQueuedCards(fetchLimit: 1, intradayLearningOnly: false)
            queue = q
            guard let card = q.cards.first else {
                rendered = nil
                congrats = try? await backend.congratsInfo()
                return
            }
            rendered = try await backend.renderExistingCard(
                cardId: card.card.id, browser: false, partialRender: false)
            startedAt = Date()
        } catch {
            loadError = error
        }
    }

    private func undoTapped() async {
        guard (try? await backend.undo()) != nil else { return }
        await loadNextCard()
    }

    private func buryOrSuspend(
        _ mode: Anki_Scheduler_BuryOrSuspendCardsRequest.Mode,
        card: Anki_Scheduler_QueuedCards.QueuedCard
    ) async {
        do {
            _ = try await backend.buryOrSuspendCards(cardIds: [card.card.id], mode: mode)
            await loadNextCard()
        } catch {
            loadError = error
        }
    }

    private func showAnswer(card: Anki_Scheduler_QueuedCards.QueuedCard) async {
        showingAnswer = true
        nextStates = (try? await backend.describeNextStates(card.states)) ?? []
    }

    private func answer(_ rating: Anki_Scheduler_CardAnswer.Rating, card: Anki_Scheduler_QueuedCards.QueuedCard)
        async
    {
        let newState: Anki_Scheduler_SchedulingState
        switch rating {
        case .again: newState = card.states.again
        case .hard: newState = card.states.hard
        case .good: newState = card.states.good
        case .easy: newState = card.states.easy
        case .UNRECOGNIZED: return
        }
        var cardAnswer = Anki_Scheduler_CardAnswer()
        cardAnswer.cardID = card.card.id
        cardAnswer.currentState = card.states.current
        cardAnswer.newState = newState
        cardAnswer.rating = rating
        cardAnswer.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
        cardAnswer.millisecondsTaken = UInt32(
            max(0, min(Date().timeIntervalSince(startedAt) * 1000, Double(UInt32.max))))
        do {
            _ = try await backend.answerCard(cardAnswer)
            answeredCount += 1
            await loadNextCard()
        } catch {
            loadError = error
        }
    }

    private func replayAudio(rendered: Anki_CardRendering_RenderCardResponse) {
        let text = showingAnswer ? concat(rendered.answerNodes) : concat(rendered.questionNodes)
        let questionSide = !showingAnswer
        Task {
            guard let extracted = try? await backend.extractAvTags(text: text, questionSide: questionSide)
            else { return }
            let filenames = extracted.avTags.compactMap { tag -> String? in
                if case .soundOrVideo(let filename) = tag.value { return filename }
                return nil
            }
            soundPlayer.play(filenames, mediaFolderPath: backend.mediaFolderPath)
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
