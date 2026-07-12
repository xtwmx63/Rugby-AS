//
//  PlayerDetailView.swift
//  Rugby AS
//
//  選手の個人成績。通算(試合数・トライ・得点と内訳)、大会別の成績、
//  出場・得点した試合の一覧を確認できる。数値は常にStatEventから
//  再計算する(後から記録を直せば自動で正しくなる)。
//
//  「試合数」はメンバー表に登録された試合と、得点記録がある試合を
//  合わせて数える(メンバー表を登録しない運用でも成績が出るように)。
//

import SwiftData
import SwiftUI

struct PlayerDetailView: View {
    let player: Player

    @Query private var allMatches: [Match]
    @Query private var allEvents: [StatEvent]
    @Query private var allLineups: [MatchLineup]
    @Query private var allSubstitutions: [Substitution]
    @Query private var teams: [Team]
    @Query private var tournaments: [Tournament]

    var body: some View {
        List {
            headerSection
            totalsSection
            tournamentSection
            matchesSection
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - ヘッダー(写真と基本情報)

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                playerPhoto(size: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.title3.weight(.black))
                    HStack(spacing: 8) {
                        Text("#\(player.number)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(teamName(for: player.teamID))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 通算成績

    private var totalsSection: some View {
        let totals = scoringTotals(in: playerMatchIDs)

        return Section {
            HStack(spacing: 0) {
                statTile(value: "\(playerMatches.count)", label: "試合")
                Divider()
                statTile(value: "\(totals.tries)", label: "トライ")
                Divider()
                statTile(value: "\(totals.points)", label: "得点")
                Divider()
                statTile(value: totalPlayingMinutesText, label: "出場時間")
            }
            .padding(.vertical, 4)

            HStack {
                Text("内訳")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("T\(totals.tries)・C\(totals.conversions)・PG\(totals.penaltyGoals)・DG\(totals.dropGoals)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
            }
            .font(.subheadline)
        } header: {
            Label("通算成績", systemImage: "chart.bar.fill")
        } footer: {
            Text("出場時間は、スタメン(メンバー表)が登録された試合の記録と交代から自動計算します。")
        }
    }

    // その試合での出場分数(スタメン未登録の試合は計算不可 = nil)
    private func playingMinutes(matchID: UUID) -> Int? {
        let result = PlayingTimeCalculator.calculate(
            matchID: matchID,
            lineups: allLineups,
            substitutions: allSubstitutions,
            events: allEvents
        )
        guard result.hasStarterInfo else { return nil }
        return result.minutesByPlayer[player.id] ?? 0
    }

    private var totalPlayingMinutesText: String {
        var total = 0
        var hasAnyComputableMatch = false
        for match in playerMatches {
            if let minutes = playingMinutes(matchID: match.id) {
                total += minutes
                hasAnyComputableMatch = true
            }
        }
        return hasAnyComputableMatch ? "\(total)分" : "—"
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title2.weight(.black).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 大会別成績

    private var tournamentSection: some View {
        Section {
            if tournamentSummaries.isEmpty {
                Text("記録がまだありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tournamentSummaries) { summary in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("\(summary.matchCount)試合")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(summary.tries)トライ・\(summary.points)点")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
            }
        } header: {
            Label("大会別成績", systemImage: "trophy")
        }
    }

    // MARK: - 試合一覧

    private var matchesSection: some View {
        Section {
            if playerMatches.isEmpty {
                Text("試合がまだありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playerMatches) { match in
                    NavigationLink {
                        MatchSummaryView(match: match)
                    } label: {
                        matchRow(match)
                    }
                }
            }
        } header: {
            Label("試合", systemImage: "sportscourt")
        } footer: {
            Text("メンバー表に登録された試合と、得点記録のある試合を表示しています。")
        }
    }

    private func matchRow(_ match: Match) -> some View {
        let contribution = contributionText(matchID: match.id)

        return VStack(alignment: .leading, spacing: 3) {
            Text(Self.dateFormatter.string(from: match.playedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("\(teamName(for: match.homeTeamID)) vs \(teamName(for: match.awayTeamID))")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()

                if let minutes = playingMinutes(matchID: match.id) {
                    Text("\(minutes)分")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !contribution.isEmpty {
                    Text(contribution)
                        .font(.caption.weight(.black).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.blue.opacity(0.75)))
                }
            }
        }
    }

    // MARK: - 集計

    private struct ScoringTotals {
        var tries = 0
        var conversions = 0
        var penaltyGoals = 0
        var dropGoals = 0
        var points = 0
    }

    private struct TournamentSummary: Identifiable {
        let id: UUID
        let name: String
        let matchCount: Int
        let tries: Int
        let points: Int
    }

    // この選手の成功した得点イベント
    private var playerScoringEvents: [StatEvent] {
        allEvents.filter { event in
            event.playerID == player.id
                && event.outcome == "success"
                && ScoringCategory(rawValue: event.category) != nil
        }
    }

    // メンバー表登録 or 得点記録のある試合ID
    private var playerMatchIDs: Set<UUID> {
        let lineupMatchIDs = allLineups
            .filter { $0.playerID == player.id }
            .map(\.matchID)
        let eventMatchIDs = playerScoringEvents.map(\.matchID)
        return Set(lineupMatchIDs).union(eventMatchIDs)
    }

    private var playerMatches: [Match] {
        allMatches
            .filter { playerMatchIDs.contains($0.id) }
            .sorted { $0.playedAt > $1.playedAt }
    }

    private func scoringTotals(in matchIDs: Set<UUID>) -> ScoringTotals {
        var totals = ScoringTotals()
        for event in playerScoringEvents where matchIDs.contains(event.matchID) {
            switch ScoringCategory(rawValue: event.category) {
            case .tryScore:
                totals.tries += 1
                totals.points += 5
            case .conversion:
                totals.conversions += 1
                totals.points += 2
            case .penaltyGoal:
                totals.penaltyGoals += 1
                totals.points += 3
            case .dropGoal:
                totals.dropGoals += 1
                totals.points += 3
            case nil:
                break
            }
        }
        return totals
    }

    private var tournamentSummaries: [TournamentSummary] {
        let matchesByTournament = Dictionary(grouping: playerMatches, by: \.tournamentID)

        return matchesByTournament
            .map { tournamentID, matches -> TournamentSummary in
                let matchIDs = Set(matches.map(\.id))
                let totals = scoringTotals(in: matchIDs)
                return TournamentSummary(
                    id: tournamentID,
                    name: tournaments.first { $0.id == tournamentID }?.officialName ?? "大会未設定",
                    matchCount: matches.count,
                    tries: totals.tries,
                    points: totals.points
                )
            }
            .sorted { $0.points > $1.points }
    }

    // 1試合での貢献の短い表記(例: "2T 1C")
    private func contributionText(matchID: UUID) -> String {
        let totals = scoringTotals(in: [matchID])
        var parts: [String] = []
        if totals.tries > 0 { parts.append("\(totals.tries)T") }
        if totals.conversions > 0 { parts.append("\(totals.conversions)C") }
        if totals.penaltyGoals > 0 { parts.append("\(totals.penaltyGoals)PG") }
        if totals.dropGoals > 0 { parts.append("\(totals.dropGoals)DG") }
        return parts.joined(separator: " ")
    }

    // MARK: - 小さな部品

    private var displayName: String {
        player.name?.isEmpty == false ? player.name! : "#\(player.number)"
    }

    private func teamName(for teamID: UUID) -> String {
        teams.first { $0.id == teamID }?.name ?? "チーム未設定"
    }

    @ViewBuilder
    private func playerPhoto(size: CGFloat) -> some View {
        if let imagePath = player.imagePath, let uiImage = ImageStorage.image(named: imagePath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        PlayerDetailView(player: Player(teamID: UUID(), number: 10, name: "山田 太郎"))
    }
    .modelContainer(for: [
        Team.self,
        Player.self,
        Tournament.self,
        Match.self,
        StatEvent.self,
        MatchLineup.self,
        Substitution.self
    ], inMemory: true)
}
