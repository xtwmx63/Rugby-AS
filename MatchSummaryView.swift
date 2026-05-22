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
            matchupHeaderSection
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

    private var matchupHeaderSection: some View {
        Section {
            HStack(spacing: 16) {
                teamLogoColumn(teamID: match.homeTeamID)

                Text("vs")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                teamLogoColumn(teamID: match.awayTeamID)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func teamLogoColumn(teamID: UUID) -> some View {
        VStack(spacing: 6) {
            teamLogoThumbnail(teamID: teamID)
            Text(teamName(for: teamID))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func teamLogoThumbnail(teamID: UUID) -> some View {
        let team = teams.first { $0.id == teamID }
        if let team, let logoName = team.logoPath, let uiImage = ImageStorage.image(named: logoName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.secondary)
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
            HStack {
                Text("種別")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                summaryTeamHeader(match.homeTeamID)
                summaryTeamHeader(match.awayTeamID)
            }

            scoringComparisonRow(.tryScore)
            scoringComparisonRow(.conversion)
            scoringComparisonRow(.penaltyGoal)
            scoringComparisonRow(.dropGoal)

            HStack {
                Text("合計")
                    .font(.headline)
                Spacer()
                Text("\(score(for: match.homeTeamID))点")
                    .font(.headline.monospacedDigit())
                    .frame(width: 72, alignment: .trailing)
                Text("\(score(for: match.awayTeamID))点")
                    .font(.headline.monospacedDigit())
                    .frame(width: 72, alignment: .trailing)
            }
        }
    }

    private var setPieceSection: some View {
        Section("セットプレー") {
            HStack {
                Text("種別")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                summaryTeamHeader(match.homeTeamID)
                summaryTeamHeader(match.awayTeamID)
            }

            setPieceComparisonRow(title: "ラインアウト", category: "lineout")
            setPieceComparisonRow(title: "スクラム", category: "scrum")
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

    private func score(for teamID: UUID) -> Int {
        scoringEvents
            .filter { $0.teamID == teamID }
            .reduce(0) { partialResult, event in
                partialResult + scoreValue(for: event)
            }
    }

    private func scoringComparisonRow(_ category: ScoringCategory) -> some View {
        HStack {
            Text(category.displayName)
            Spacer()
            Text("\(countScoring(category, teamID: match.homeTeamID))回")
                .font(.body.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
            Text("\(countScoring(category, teamID: match.awayTeamID))回")
                .font(.body.monospacedDigit())
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func summaryTeamHeader(_ teamID: UUID) -> some View {
        Text(teamName(for: teamID))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 72, alignment: .trailing)
    }

    private func possessionRow(teamID: UUID, seconds: Int, ratio: Double) -> some View {
        HStack {
            Text(teamName(for: teamID))
            Spacer()
            Text("\(percentText(ratio)) / \(timeText(seconds))")
                .font(.body.monospacedDigit())
        }
    }

    private func setPieceComparisonRow(title: String, category: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            setPieceSummary(category: category, teamID: match.homeTeamID)
            setPieceSummary(category: category, teamID: match.awayTeamID)
        }
    }

    private func setPieceSummary(category: String, teamID: UUID) -> some View {
        let events = setPieceEvents.filter { $0.category == category && $0.teamID == teamID }
        let successCount = events.filter { $0.outcome == "success" }.count
        let totalCount = events.count
        let rate = totalCount == 0 ? 0 : Double(successCount) / Double(totalCount)

        return VStack(alignment: .trailing, spacing: 2) {
            Text(percentText(rate))
                .font(.body.monospacedDigit())
            Text("\(successCount)/\(totalCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 72, alignment: .trailing)
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

    private func countScoring(_ category: ScoringCategory, teamID: UUID) -> Int {
        scoringEvents.filter { $0.category == category.rawValue && $0.teamID == teamID }.count
    }

    private func scoreValue(for event: StatEvent) -> Int {
        guard event.outcome == "success" else { return 0 }

        switch ScoringCategory(rawValue: event.category) {
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
