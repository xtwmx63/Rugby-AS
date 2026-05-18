//
//  MatchSummaryView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import SwiftData
import SwiftUI

struct MatchSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query private var allEvents: [StatEvent]
    @Query private var teams: [Team]

    let match: Match

    @State private var scoringEventForPlayerSelection: StatEvent?

    private var players: [Player] {
        allPlayers
            .filter { $0.teamID == match.homeTeamID || $0.teamID == match.awayTeamID }
            .sorted { lhs, rhs in
                if lhs.teamID == rhs.teamID {
                    return lhs.number < rhs.number
                }
                return lhs.teamID == match.homeTeamID
            }
    }

    private var matchEvents: [StatEvent] {
        allEvents.filter { $0.matchID == match.id }
    }

    private var possessionEvents: [StatEvent] {
        matchEvents.filter { $0.category == "possession" }
    }

    private var scoringEvents: [StatEvent] {
        matchEvents
            .filter { ScoringCategory(rawValue: $0.category) != nil }
            .sorted { ($0.half, $0.seconds) < ($1.half, $1.seconds) }
    }

    private var setPieceEvents: [StatEvent] {
        matchEvents.filter { $0.category == "lineout" || $0.category == "scrum" }
    }

    var body: some View {
        List {
            possessionSection
            scoringSummarySection
            setPieceSection
            scorerTimelineSection
        }
        .navigationTitle("サマリー")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("記録へ") {
                    V3RecordingView(match: match)
                }
            }
        }
        .sheet(item: $scoringEventForPlayerSelection) { event in
            PlayerSelectionSheet(players: players, title: "得点者を選択") { player in
                event.playerID = player?.id
                try? modelContext.save()
                scoringEventForPlayerSelection = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var possessionSection: some View {
        Section("ポゼッション") {
            let homeSeconds = possessionSeconds(teamID: match.homeTeamID)
            let awaySeconds = possessionSeconds(teamID: match.awayTeamID)
            let bipSeconds = bipTotalSeconds(homeSeconds: homeSeconds, awaySeconds: awaySeconds)
            let homeRatio = bipSeconds == 0 ? 0 : Double(homeSeconds) / Double(bipSeconds)
            let awayRatio = bipSeconds == 0 ? 0 : Double(awaySeconds) / Double(bipSeconds)
            let unclaimedRatio = max(0, 1 - homeRatio - awayRatio)

            VStack(alignment: .leading, spacing: 10) {
                possessionRow(teamID: match.homeTeamID, seconds: homeSeconds, ratio: homeRatio)

                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(.blue)
                            .frame(width: proxy.size.width * homeRatio)
                        Rectangle()
                            .fill(.green)
                            .frame(width: proxy.size.width * awayRatio)
                        Rectangle()
                            .fill(.gray.opacity(0.35))
                            .frame(width: proxy.size.width * unclaimedRatio)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 14)

                possessionRow(teamID: match.awayTeamID, seconds: awaySeconds, ratio: awayRatio)

                HStack {
                    Text("BIP合計")
                    Spacer()
                    Text(timeText(bipSeconds))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var scoringSummarySection: some View {
        Section("得点") {
            scoringSummaryRow(.tryScore)
            scoringSummaryRow(.conversion)
            scoringSummaryRow(.penaltyGoal)
            scoringSummaryRow(.dropGoal)

            scoreRow(teamID: match.homeTeamID)
            scoreRow(teamID: match.awayTeamID)
        }
    }

    private var setPieceSection: some View {
        Section("セットプレー") {
            setPieceRow(title: "ラインアウト", category: "lineout")
            setPieceRow(title: "スクラム", category: "scrum")
        }
    }

    private var scorerTimelineSection: some View {
        Section("得点者") {
            if scoringEvents.isEmpty {
                Text("得点記録がありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scoringEvents) { event in
                    Button {
                        scoringEventForPlayerSelection = event
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(halfLabel(event.half))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(timeText(event.seconds))
                                    .font(.body.monospacedDigit())
                            }
                            .frame(width: 60, alignment: .leading)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(scoringName(event.category))
                                Text(playerName(for: event.playerID))
                                    .font(.caption)
                                    .foregroundStyle(event.playerID == nil ? .orange : .secondary)
                            }

                            Spacer()
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteEvent(event)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func scoreRow(teamID: UUID) -> some View {
        HStack {
            Text(teamName(for: teamID))
                .font(.headline)
            Spacer()
            Text("\(score(for: teamID))点")
                .font(.headline.monospacedDigit())
        }
    }

    private func score(for teamID: UUID) -> Int {
        scoringEvents
            .filter { $0.teamID == teamID }
            .reduce(0) { partialResult, event in
                partialResult + scoreValue(for: event.category)
            }
    }

    private func scoringSummaryRow(_ category: ScoringCategory) -> some View {
        HStack {
            Text(category.displayName)
            Spacer()
            Text("\(countScoring(category))回")
                .font(.body.monospacedDigit())
        }
    }

    private func possessionRow(teamID: UUID, seconds: Int, ratio: Double) -> some View {
        HStack {
            Text(teamName(for: teamID))
            Spacer()
            Text("\(percentText(ratio)) / \(timeText(seconds))")
                .font(.body.monospacedDigit())
        }
    }

    private func setPieceRow(title: String, category: String) -> some View {
        let events = setPieceEvents.filter { $0.category == category }
        let successCount = events.filter { $0.outcome == "success" }.count
        let totalCount = events.count
        let rate = totalCount == 0 ? 0 : Double(successCount) / Double(totalCount)

        return HStack {
            Text(title)
            Spacer()
            Text("\(successCount)/\(totalCount)")
                .font(.body.monospacedDigit())
            Text(percentText(rate))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func possessionSeconds(teamID: UUID) -> Int {
        let teamOwnedSeconds = possessionEvents
            .filter { $0.teamID == teamID }
            .reduce(0) { $0 + $1.seconds }

        if teamOwnedSeconds > 0 {
            return teamOwnedSeconds
        }

        if teamID == match.homeTeamID {
            return possessionEvents
                .filter { $0.teamID == nil && $0.outcome == "own" }
                .reduce(0) { $0 + $1.seconds }
        }

        return possessionEvents
            .filter { $0.teamID == nil && $0.outcome == "opponent" }
            .reduce(0) { $0 + $1.seconds }
    }

    private func bipTotalSeconds(homeSeconds: Int, awaySeconds: Int) -> Int {
        let recordedBIPSeconds = possessionEvents
            .filter { $0.outcome == "none" }
            .reduce(0) { $0 + $1.seconds }

        if recordedBIPSeconds > 0 {
            return recordedBIPSeconds
        }

        return homeSeconds + awaySeconds
    }

    private func countScoring(_ category: ScoringCategory) -> Int {
        scoringEvents.filter { $0.category == category.rawValue }.count
    }

    private func scoreValue(for category: String) -> Int {
        switch ScoringCategory(rawValue: category) {
        case .tryScore:
            return 5
        case .conversion:
            return 2
        case .penaltyGoal, .dropGoal:
            return 3
        case nil:
            return 0
        }
    }

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
    }

    private func scoringName(_ category: String) -> String {
        ScoringCategory(rawValue: category)?.displayName ?? category
    }

    private func playerName(for playerID: UUID?) -> String {
        guard let playerID, let player = players.first(where: { $0.id == playerID }) else {
            return "未設定"
        }

        if let name = player.name, !name.isEmpty {
            return "#\(player.number) \(name)"
        }
        return "#\(player.number) 名前未設定"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func halfLabel(_ half: Int) -> String {
        half >= 1 ? "後半" : "前半"
    }

    private func deleteEvent(_ event: StatEvent) {
        modelContext.delete(event)
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        MatchSummaryView(match: Match(tournamentID: UUID(), homeTeamID: UUID(), awayTeamID: UUID(), playedAt: Date()))
    }
    .modelContainer(for: [
        Team.self,
        Player.self,
        Tournament.self,
        Match.self,
        StatEvent.self,
        Substitution.self
    ], inMemory: true)
}
