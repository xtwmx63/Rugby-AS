//
//  ContentView.swift
//  Rugby AS
//
//  Created by 35 on 2026/05/17.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Match.playedAt, order: .reverse) private var matches: [Match]
    @Query private var teams: [Team]
    @Query private var tournaments: [Tournament]
    @Query private var events: [StatEvent]
    @State private var isShowingCreateMatch = false
    @State private var matchPendingDeletion: Match?
    @State private var selectedFilter: MatchFilter = .all
    @State private var selectedMatch: Match?
    @State private var isTeamListPresented = false
    @State private var isTournamentExportPresented = false

    private enum MatchFilter: String, CaseIterable, Identifiable {
        case all
        case recording
        case finished

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "すべて"
            case .recording: return "記録中"
            case .finished: return "終了"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                matchListBackground.ignoresSafeArea()

                if matches.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            topHeader
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                            filterBar
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        ForEach(groupedMatches, id: \.key) { group in
                            Section {
                                ForEach(group.matches) { match in
                                    Button {
                                        selectedMatch = match
                                    } label: {
                                        MatchCard(
                                            match: match,
                                            tournamentName: tournamentName(for: match),
                                            homeTeam: team(for: match.homeTeamID),
                                            awayTeam: team(for: match.awayTeamID),
                                            isFinished: isFinished(match),
                                            homeScore: score(for: match, teamID: match.homeTeamID),
                                            awayScore: score(for: match, teamID: match.awayTeamID),
                                            homeFirstHalfScore: score(for: match, teamID: match.homeTeamID, half: 0),
                                            awayFirstHalfScore: score(for: match, teamID: match.awayTeamID, half: 0),
                                            homeSecondHalfScore: score(for: match, teamID: match.homeTeamID, half: 1),
                                            awaySecondHalfScore: score(for: match, teamID: match.awayTeamID, half: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("削除", role: .destructive) {
                                            matchPendingDeletion = match
                                        }
                                    }
                                }
                            } header: {
                                HStack(spacing: 10) {
                                    Text(group.title)
                                        .font(.headline.weight(.black))
                                        .foregroundStyle(.white.opacity(0.72))
                                    Rectangle()
                                        .fill(Color.white.opacity(0.14))
                                        .frame(height: 1)
                                }
                                .textCase(nil)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 2, trailing: 16))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 96, for: .scrollContent)
                }

                bottomTabBar
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedMatch) { match in
                matchDestination(for: match)
            }
            .navigationDestination(isPresented: $isTeamListPresented) {
                TeamListView()
            }
            .sheet(isPresented: $isShowingCreateMatch) {
                NavigationStack {
                    CreateMatchView()
                }
            }
            .sheet(isPresented: $isTournamentExportPresented) {
                TournamentCSVExportSheet()
            }
            .alert(
                "この試合を削除しますか？",
                isPresented: Binding(
                    get: { matchPendingDeletion != nil },
                    set: { if !$0 { matchPendingDeletion = nil } }
                ),
                presenting: matchPendingDeletion
            ) { match in
                Button("削除する", role: .destructive) {
                    deleteMatch(match)
                }
                Button("キャンセル", role: .cancel) { }
            } message: { match in
                Text(deletionMessage(for: match))
            }
        }
    }

    private var matchListBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.01, green: 0.04, blue: 0.08),
                Color(red: 0.02, green: 0.08, blue: 0.13),
                Color(red: 0.01, green: 0.03, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            topHeader
            Spacer()
            Image(systemName: "sportscourt")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text("試合がありません")
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
            Text("右上の＋から試合を追加します。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.56))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 96)
    }

    private var topHeader: some View {
        ZStack {
            Text("試合一覧")
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack {
                Button {
                    isTeamListPresented = true
                } label: {
                    Image(systemName: "person.3")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    isTournamentExportPresented = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .accessibilityLabel("大会ごとのCSV書き出し")
                .buttonStyle(.plain)

                Spacer()

                Button {
                    isShowingCreateMatch = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(color: .blue.opacity(0.28), radius: 10, y: 5)
                }
                .accessibilityLabel("試合を追加")
                .buttonStyle(.plain)
            }
        }
        .frame(height: 48)
    }

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(MatchFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    VStack(spacing: 1) {
                        Text(filter.title)
                            .font(.caption.weight(.black))
                        Text("\(count(for: filter))")
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                    .foregroundStyle(selectedFilter == filter ? .white : .white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(selectedFilter == filter ? Color.blue : Color.clear)
                }
                .buttonStyle(.plain)

                if filter != MatchFilter.allCases.last {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 22)
                }
            }
        }
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var bottomTabBar: some View {
        HStack {
            bottomTabItem("ホーム", systemImage: "house", isSelected: false)
            bottomTabItem("記録", systemImage: "pencil", isSelected: false)
            bottomTabItem("試合一覧", systemImage: "trophy", isSelected: true)
            NavigationLink {
                TeamListView()
            } label: {
                bottomTabItem("チーム", systemImage: "person.3", isSelected: false)
            }
            .buttonStyle(.plain)
            NavigationLink {
                SettingsView()
            } label: {
                bottomTabItem("設定", systemImage: "gearshape", isSelected: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(red: 0.03, green: 0.09, blue: 0.14).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func bottomTabItem(_ title: String, systemImage: String, isSelected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(isSelected ? Color.blue : Color.white.opacity(0.58))
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func matchDestination(for match: Match) -> some View {
        if isFinished(match) {
            MatchSummaryView(match: match)
        } else {
            LineupRegistrationView(match: match)
        }
    }

    private var filteredMatches: [Match] {
        matches.filter { match in
            switch selectedFilter {
            case .all:
                return true
            case .recording:
                return !isFinished(match)
            case .finished:
                return isFinished(match)
            }
        }
    }

    private var groupedMatches: [(key: String, title: String, matches: [Match])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredMatches) { match in
            let components = calendar.dateComponents([.year, .month], from: match.playedAt)
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        }

        return grouped.keys.sorted(by: >).compactMap { key in
            guard let matches = grouped[key], let first = matches.first else { return nil }
            return (key, monthTitle(for: first.playedAt), matches)
        }
    }

    private func count(for filter: MatchFilter) -> Int {
        matches.filter { match in
            switch filter {
            case .all: return true
            case .recording: return !isFinished(match)
            case .finished: return isFinished(match)
            }
        }.count
    }

    private func team(for id: UUID) -> Team? {
        teams.first { $0.id == id }
    }

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
    }

    private func tournamentName(for match: Match) -> String {
        tournaments.first { $0.id == match.tournamentID }?.officialName ?? "大会未設定"
    }

    private func isFinished(_ match: Match) -> Bool {
        events.contains { event in
            event.matchID == match.id && event.category == "match_state" && event.outcome == "finished"
        }
    }

    private func score(for match: Match, teamID: UUID, half: Int? = nil) -> Int {
        events
            .filter { event in
                event.matchID == match.id
                    && event.teamID == teamID
                    && (half == nil || event.half == half)
                    && ScoringCategory(rawValue: event.category) != nil
            }
            .reduce(0) { $0 + scoreValue(for: $1) }
    }

    private func scoreValue(for event: StatEvent) -> Int {
        guard event.outcome == "success" else { return 0 }
        switch ScoringCategory(rawValue: event.category) {
        case .tryScore: return 5
        case .conversion: return 2
        case .penaltyGoal, .dropGoal: return 3
        case nil: return 0
        }
    }

    private func monthTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .month) &&
            calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return "今月の試合"
        }
        let month = calendar.component(.month, from: date)
        return "\(month)月"
    }

    private func dateText(_ date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ja_JP")))
        return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " (\(weekday))"
    }

    private func deletionMessage(for match: Match) -> String {
        let date = match.playedAt.formatted(date: .numeric, time: .omitted)
        return "\(teamName(for: match.homeTeamID)) vs \(teamName(for: match.awayTeamID))\n\(date)\n\n記録したスタッツもすべて削除され、元に戻せません。"
    }

    private func deleteMatch(_ match: Match) {
        // SwiftData の @Relationship は未定義のため関連データは自動削除されない。
        // 孤児を残さないよう、この試合に紐づくものを明示的に全部片付ける。
        let matchID = match.id

        // 記録(スタッツ)
        for event in events where event.matchID == matchID {
            modelContext.delete(event)
        }
        // メンバー表
        if let lineups = try? modelContext.fetch(
            FetchDescriptor<MatchLineup>(predicate: #Predicate { $0.matchID == matchID })
        ) {
            for lineup in lineups {
                modelContext.delete(lineup)
            }
        }
        // 交代(V1では作られないが、あれば片付ける)
        if let substitutions = try? modelContext.fetch(
            FetchDescriptor<Substitution>(predicate: #Predicate { $0.matchID == matchID })
        ) {
            for substitution in substitutions {
                modelContext.delete(substitution)
            }
        }

        // 端末に置いた動画ファイルと試合時間設定
        VideoStorage.deleteVideo(for: matchID)
        MatchClockSettingsCleanup.removeSettings(for: matchID)

        modelContext.delete(match)
        try? modelContext.save()
    }
}

private struct MatchCard: View {
    let match: Match
    let tournamentName: String
    let homeTeam: Team?
    let awayTeam: Team?
    let isFinished: Bool
    let homeScore: Int
    let awayScore: Int
    let homeFirstHalfScore: Int
    let awayFirstHalfScore: Int
    let homeSecondHalfScore: Int
    let awaySecondHalfScore: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text(tournamentName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Text(dateText(match.playedAt))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.56))
                    }

                    HStack(alignment: .center, spacing: 8) {
                        matchTeamLogo(team: homeTeam)
                            .padding(.leading, 14)

                        scoreLine
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1)

                        matchTeamLogo(team: awayTeam)
                            .padding(.trailing, 14)
                    }

                    HStack(spacing: 8) {
                        matchTeamName(homeTeam)

                        Spacer(minLength: 6)

                        Text("前半 \(homeFirstHalfScore)-\(awayFirstHalfScore) / 後半 \(homeSecondHalfScore)-\(awaySecondHalfScore)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.56))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Spacer(minLength: 6)

                        matchTeamName(awayTeam)
                    }
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)

            Text(isFinished ? "終了" : "記録中")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isFinished ? Color.white.opacity(0.13) : Color.blue)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, bottomTrailingRadius: 12))
        }
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color(red: 0.03, green: 0.09, blue: 0.14))
        )
        .overlay(
            Group {
                if isFinished {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1.2)
                } else {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(
                            LinearGradient(colors: [.blue, .red], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1.2
                        )
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private var scoreLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            scoreNumberText(homeScore, color: scoreColor(for: .home), side: .home)
            Text("-")
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 20, alignment: .center)
            scoreNumberText(awayScore, color: scoreColor(for: .away), side: .away)
        }
        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: 152)
    }

    private enum ScoreSide {
        case home
        case away
    }

    private func scoreColor(for side: ScoreSide) -> Color {
        if homeScore == awayScore {
            return .white.opacity(0.82)
        }
        switch side {
        case .home:
            return homeScore > awayScore ? .blue : .white.opacity(0.82)
        case .away:
            return awayScore > homeScore ? .red : .white.opacity(0.82)
        }
    }

    private func scoreNumberText(_ score: Int, color: Color, side: ScoreSide) -> some View {
        let text = "\(score)"
        let digitWidth: CGFloat = 18
        let fullWidth = digitWidth * 3
        let twoDigitWidth = digitWidth * 2
        let innerAlignment: Alignment = side == .home ? .trailing : .leading

        return Group {
            if text.count == 1 {
                Text(text)
                    .foregroundStyle(color)
                    .frame(width: twoDigitWidth, alignment: .center)
                    .frame(width: fullWidth, alignment: innerAlignment)
            } else {
                Text(text)
                    .foregroundStyle(color)
                    .frame(width: fullWidth, alignment: innerAlignment)
            }
        }
    }

    private func matchTeamLogo(team: Team?) -> some View {
        teamLogo(team: team)
            .frame(width: 56, height: 56)
    }

    private func matchTeamName(_ team: Team?) -> some View {
        Text(team?.name ?? "チーム未設定")
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 88)
    }

    @ViewBuilder
    private func teamLogo(team: Team?) -> some View {
        if let team, let logoPath = team.logoPath, let image = ImageStorage.image(named: logoPath) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.gray)
                .padding(10)
                .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    private func dateText(_ date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "ja_JP")))
        return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " (\(weekday))"
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Team.self,
            Player.self,
            Tournament.self,
            Match.self,
            StatEvent.self,
            Substitution.self
        ], inMemory: true)
}
