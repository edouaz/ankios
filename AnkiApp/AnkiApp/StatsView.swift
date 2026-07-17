// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI

struct StatsView: View {
    let backend: Backend

    @State private var graphs: Anki_Stats_GraphsResponse?
    @State private var loadError: Error?

    var body: some View {
        NavigationStack {
            Group {
                if let graphs {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            summary(graphs)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Review Activity")
                                    .font(.headline)
                                HeatmapView(counts: dailyCounts(graphs))
                            }
                        }
                        .padding()
                    }
                } else if loadError != nil {
                    ContentUnavailableView(
                        "Couldn't Load Stats", systemImage: "chart.bar",
                        description: Text(String(describing: loadError!)))
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Stats")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Summary tiles

    @ViewBuilder
    private func summary(_ g: Anki_Stats_GraphsResponse) -> some View {
        let counts = dailyCounts(g)
        let yearTotal = counts.values.reduce(0, +)
        let answered = Int(g.today.answerCount)
        let retention =
            answered > 0 ? "\(Int(Double(g.today.correctCount) / Double(answered) * 100))%" : "—"
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("Reviews Today", "\(answered)", "checkmark.circle", .green)
            tile("Retention Today", retention, "target", .blue)
            tile("Current Streak", "\(streak(counts)) d", "flame.fill", .orange)
            tile("Reviews / Year", "\(yearTotal)", "calendar", .purple)
        }
    }

    private func tile(_ title: String, _ value: String, _ symbol: String, _ color: Color)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(color)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.title2.bold())
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    // MARK: Data

    /// day offset (0 = today, negative = past) → total reviews that day.
    private func dailyCounts(_ g: Anki_Stats_GraphsResponse) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for (day, r) in g.reviews.count {
            out[Int(day)] = Int(r.learn + r.relearn + r.young + r.mature + r.filtered)
        }
        return out
    }

    /// Consecutive days with at least one review, counting back from today.
    private func streak(_ counts: [Int: Int]) -> Int {
        var n = 0
        while (counts[-n] ?? 0) > 0 { n += 1 }
        return n
    }

    private func load() async {
        do {
            graphs = try await backend.graphs(search: "", days: 365)
        } catch {
            loadError = error
        }
    }
}

/// GitHub-style calendar heatmap. Columns = weeks (oldest → newest), rows =
/// weekday (Sun…Sat). The bottom-right cell is today.
private struct HeatmapView: View {
    let counts: [Int: Int]  // day offset → reviews

    private let weeks = 53
    private let cell: CGFloat = 12
    private let spacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(0..<weeks, id: \.self) { col in
                            VStack(spacing: spacing) {
                                ForEach(0..<7, id: \.self) { row in
                                    cellView(col: col, row: row)
                                }
                            }
                            .id(col)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(weeks - 1, anchor: .trailing) }
            }
            legend
        }
    }

    private var weekdayToday: Int {
        Calendar.current.component(.weekday, from: Date()) - 1  // 0 = Sun
    }

    private func offset(col: Int, row: Int) -> Int {
        -((weeks - 1 - col) * 7 + (weekdayToday - row))
    }

    @ViewBuilder
    private func cellView(col: Int, row: Int) -> some View {
        let off = offset(col: col, row: row)
        if off > 0 {
            Color.clear.frame(width: cell, height: cell)  // future day
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(color(for: counts[off] ?? 0))
                .frame(width: cell, height: cell)
        }
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.gray.opacity(0.18)
        case 1...3: return .green.opacity(0.35)
        case 4...9: return .green.opacity(0.55)
        case 10...19: return .green.opacity(0.75)
        default: return .green
        }
    }

    private var legend: some View {
        HStack(spacing: spacing) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach([0, 2, 6, 12, 25], id: \.self) { c in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: c))
                    .frame(width: cell, height: cell)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
