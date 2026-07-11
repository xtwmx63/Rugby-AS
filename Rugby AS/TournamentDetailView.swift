//
//  TournamentDetailView.swift
//  Rugby AS
//
//  大会の詳細。一般的なスポーツアプリのように、
//  順位表(チーム成績)・トライランキング・得点ランキング・試合一覧を
//  1画面で確認できる。数値は保存値でなく常にStatEventから再計算する
//  (後から記録を直しても自動で正しくなる、このアプリの基本方針)。
//

import SwiftData
import SwiftUI

struct TournamentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let tournament: Tournament

    @Query private var allMatches: [Match]
    @Query private var allEvents: [StatEvent]
    @Query private var teams: [Team]
    @Query(sort: \Player.number) private var players: [Player]

    var body: some View {
        List {
            standingsSection
            rankingSection(
                title: "トライランキング",
                systemImage: "rugbyball.fill",
                entries: tryRanking,
                unit: "トライ"
            )
            rankingSection(
                title: "得点ランキング",
                systemImage: "star.fill",
                entries: pointsRanking,
                unit: "点"
            )
            matchesSection
        }
        .navigationTitle(tournament.officialName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(
                    item: TournamentCSVExportRequest(
                        container: modelContext.container,
                        tournamentID: tournament.id,
                        tournamentName: tournament.officialName
                    ),
                    preview: SharePreview("\(tournament.officialName) 全試合CSV")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(tournamentMatches.isEmpty)
                .accessibilityLabel("この大会のCSVを書き出す")
            }
        }
    }

    // MARK: - 順位表(チーム成績)

    private var standingsSection: some View {
        Section {
            if standings.isEmpty {
                Text("試合がまだありません")
                    .foregroundStyle(.secondary)
            } else {
                // 見出し行
                HStack(spacing: 8) {
                    Text("#").frame(width: 22)
                    Text("チーム").frame(maxWidth: .infinity, alignment: .leading)
                    Text("試合").frame(width: 34)
                    Text("勝-分-敗").frame(width: 62)
                    Text("得失").frame(width: 44, alignment: .trailing)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.black).monospacedDigit())
                            .foregroundStyle(index == 0 ? Color.yellow : .secondary)
                            .frame(width: 22)

                        teamThumbnail(for: standing.team)

                        Text(standing.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(standing.played)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34)

                        Text("\(standing.wins)-\(standing.draws)-\(standing.losses)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .frame(width: 62)

                        Text(standing.diff > 0 ? "+\(standing.diff)" : "\(standing.diff)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(standing.diff > 0 ? .green : (standing.diff < 0 ? .red : .secondary))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        } header: {
            Label("順位表", systemImage: "list.number")
        } footer: {
            if !standings.isEmpty {
                Text("勝ち数→得失点差の順で並べています。")
            }
        }
    }

    // MARK: - ランキング(トライ/得点 共通の見た目)

    private func rankingSection(
        title: String,
        systemImage: String,
        entries: [RankingEntry],
        unit: String
    ) -> some View {
        Section {
            if entries.isEmpty {
                Text("選手が記録された得点がまだありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink {
                        if let player = players.first(where: { $0.id == entry.id }) {
                            PlayerDetailView(player: player)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            rankBadge(index + 1)
                            playerThumbnail(imagePath: entry.playerImagePath)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.playerName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(entry.teamName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(entry.value)")
                                    .font(.title3.weight(.black).monospacedDigit())
                                Text(unit)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Label(title, systemImage: systemImage)
        }
    }

    // 1位=金、2位=銀、3位=銅の丸バッジ
    private func rankBadge(_ rank: Int) -> some View {
        let color: Color = switch rank {
        case 1: .yellow
        case 2: Color(white: 0.72)
        case 3: .orange
        default: Color.secondary.opacity(0.25)
        }
        return Text("\(rank)")
            .font(.footnote.weight(.black).monospacedDigit())
            .foregroundStyle(rank <= 3 ? .black : .primary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(color))
    }

    // MARK: - 試合一覧

    private var matchesSection: some View {
        Section {
            if tournamentMatches.isEmpty {
                Text("試合がまだありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tournamentMatches) { match in
                    NavigationLink {
                        MatchSummaryView(match: match)
                    } label: {
                        matchRow(match)
                    }
                }
            }
        } header: {
            Label("試合一覧", systemImage: "sportscourt")
        }
    }

    private func matchRow(_ match: Match) -> some View {
        let homeScore = score(matchID: match.id, teamID: match.homeTeamID)
        let awayScore = score(matchID: match.id, teamID: match.awayTeamID)

        return VStack(alignment: .leading, spacing: 3) {
            Text(Self.dateFormatter.string(from: match.playedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(teamName(for: match.homeTeamID))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(homeScore) - \(awayScore)")
                    .font(.subheadline.weight(.black).monospacedDigit())
                Text(teamName(for: match.awayTeamID))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - 集計

    private struct RankingEntry: Identifiable {
        let id: UUID
        let playerName: String
        let playerImagePath: String?
        let teamName: String
        let value: Int
    }

    private struct TeamStanding: Identifiable {
        let id: UUID
        let team: Team?
        let name: String
        var played = 0
        var wins = 0
        var draws = 0
        var losses = 0
        var scored = 0
        var conceded = 0
        var diff: Int { scored - conceded }
    }

    private var tournamentMatches: [Match] {
        allMatches
            .filter { $0.tournamentID == tournament.id }
            .sorted { $0.playedAt > $1.playedAt }
    }

    private var tournamentEvents: [StatEvent] {
        let matchIDs = Set(tournamentMatches.map(\.id))
        return allEvents.filter { matchIDs.contains($0.matchID) }
    }

    // 成功した得点の点数(トライ5・CON2・PG/DG3)。それ以外は0
    private func points(for event: StatEvent) -> Int {
        guard event.outcome == "success" else { return 0 }
        switch ScoringCategory(rawValue: event.category) {
        case .tryScore: return 5
        case .conversion: return 2
        case .penaltyGoal, .dropGoal: return 3
        case nil: return 0
        }
    }

    // 試合ごと・チームごとの得点表 [試合ID: [チームID: 点]]
    private var scoresByMatch: [UUID: [UUID: Int]] {
        var result: [UUID: [UUID: Int]] = [:]
        for event in tournamentEvents {
            let value = points(for: event)
            guard value > 0, let teamID = event.teamID else { continue }
            result[event.matchID, default: [:]][teamID, default: 0] += value
        }
        return result
    }

    private func score(matchID: UUID, teamID: UUID) -> Int {
        scoresByMatch[matchID]?[teamID] ?? 0
    }

    private var standings: [TeamStanding] {
        var table: [UUID: TeamStanding] = [:]

        func entry(for teamID: UUID) -> TeamStanding {
            table[teamID] ?? TeamStanding(
                id: teamID,
                team: teams.first { $0.id == teamID },
                name: teamName(for: teamID)
            )
        }

        for match in tournamentMatches {
            let homeScore = score(matchID: match.id, teamID: match.homeTeamID)
            let awayScore = score(matchID: match.id, teamID: match.awayTeamID)

            var home = entry(for: match.homeTeamID)
            var away = entry(for: match.awayTeamID)

            home.played += 1
            away.played += 1
            home.scored += homeScore
            home.conceded += awayScore
            away.scored += awayScore
            away.conceded += homeScore

            if homeScore > awayScore {
                home.wins += 1
                away.losses += 1
            } else if homeScore < awayScore {
                away.wins += 1
                home.losses += 1
            } else {
                home.draws += 1
                away.draws += 1
            }

            table[home.id] = home
            table[away.id] = away
        }

        return table.values.sorted {
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            return $0.diff > $1.diff
        }
    }

    // 選手が記録された成功トライの数(選手未設定の得点はランキングに入れない)
    private var tryRanking: [RankingEntry] {
        ranking { event in
            event.category == ScoringCategory.tryScore.rawValue ? 1 : 0
        }
    }

    private var pointsRanking: [RankingEntry] {
        ranking { event in
            points(for: event)
        }
    }

    private func ranking(value: (StatEvent) -> Int) -> [RankingEntry] {
        var totals: [UUID: Int] = [:]
        for event in tournamentEvents where event.outcome == "success" {
            guard let playerID = event.playerID else { continue }
            let eventValue = value(event)
            if eventValue > 0 {
                totals[playerID, default: 0] += eventValue
            }
        }

        return totals
            .compactMap { playerID, total -> RankingEntry? in
                guard let player = players.first(where: { $0.id == playerID }) else { return nil }
                return RankingEntry(
                    id: playerID,
                    playerName: player.name ?? "#\(player.number)",
                    playerImagePath: player.imagePath,
                    teamName: teamName(for: player.teamID),
                    value: total
                )
            }
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - 小さな部品

    private func teamName(for teamID: UUID) -> String {
        teams.first { $0.id == teamID }?.name ?? "チーム未設定"
    }

    @ViewBuilder
    private func teamThumbnail(for team: Team?) -> some View {
        if let team, let name = team.logoPath, let uiImage = ImageStorage.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func playerThumbnail(imagePath: String?) -> some View {
        if let imagePath, let uiImage = ImageStorage.image(named: imagePath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.caption)
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
        TournamentDetailView(tournament: Tournament(officialName: "サンプル大会"))
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
