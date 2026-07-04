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
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query private var matchEvents: [StatEvent]
    @Query private var teams: [Team]
    @Query private var tournaments: [Tournament]

    let match: Match

    @State private var scoringEventForPlayerSelection: StatEvent?
    @State private var isRecordingPresented = false
    @State private var isTimelineEditorPresented = false
    @State private var selectedScope: SummaryScope = .all

    private enum SummaryScope: String, CaseIterable, Identifiable {
        case all
        case first
        case second

        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全体"
            case .first: return "前半"
            case .second: return "後半"
            }
        }
        var half: Int? {
            switch self {
            case .all: return nil
            case .first: return 0
            case .second: return 1
            }
        }
    }

    private var scopeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.4 else { return }

                if horizontal < 0 {
                    moveScope(forward: true)
                } else {
                    moveScope(forward: false)
                }
            }
    }

    init(match: Match) {
        self.match = match
        let matchID = match.id
        _matchEvents = Query(filter: #Predicate<StatEvent> { event in
            event.matchID == matchID
        })
    }

    // MARK: - Derived collections

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

    private var isFinished: Bool {
        matchEvents.contains { $0.category == "match_state" && $0.outcome == "finished" }
    }

    // この試合の全記録をCSVにしたもの(共有ボタンから書き出す)
    private var csvFile: MatchCSVFile {
        MatchCSVExporter.makeFile(
            match: match,
            events: matchEvents,
            teams: teams,
            players: players,
            tournamentName: tournaments.first { $0.id == match.tournamentID }?.officialName ?? "大会未設定"
        )
    }

    // MARK: - Team accent colors

    /// HOME のカラー（明度補正後）。
    private var homeAccent: Color { balancedAccents.home }
    /// AWAY のカラー（同色補正＋明度補正後）。
    private var awayAccent: Color { balancedAccents.away }

    /// HOME / AWAY の色を「視認性が揃うように」補正したものを返す。
    private var balancedAccents: (home: Color, away: Color) {
        let rawHome = teamAccent(for: match.homeTeamID, fallback: .blue)
        let preferredAway = teamAccent(for: match.awayTeamID, fallback: .red)
        let rawAway = TeamColorPalette.nearestDistinct(
            from: preferredAway,
            against: rawHome,
            minDistance: 0.15
        )

        let homeBrightness = rawHome.hsbBrightness
        let awayBrightness = rawAway.hsbBrightness
        let gap = abs(homeBrightness - awayBrightness)

        if gap > 0.18 {
            let target = max(0.80, min(0.95, (homeBrightness + awayBrightness) / 2))
            return (rawHome.withBrightness(target), rawAway.withBrightness(target))
        }

        let minBrightness = 0.75
        let home = homeBrightness < minBrightness
            ? rawHome.withBrightness(minBrightness)
            : rawHome
        let away = awayBrightness < minBrightness
            ? rawAway.withBrightness(minBrightness)
            : rawAway
        return (home, away)
    }

    private func teamAccent(for teamID: UUID, fallback: Color) -> Color {
        guard let team = teams.first(where: { $0.id == teamID }),
              let hex = team.colorHex,
              let color = Color(hex: hex)
        else {
            return fallback
        }
        return color
    }

    /// 各得点イベント時点での「ここまでの累計スコア」を返す。
    /// scoringEvents が時系列ソート済みであることに依存。
    private var scoringProgression: [UUID: (home: Int, away: Int)] {
        var home = 0
        var away = 0
        var map: [UUID: (Int, Int)] = [:]
        for event in scoringEvents {
            let value = scoreValue(for: event)
            if event.teamID == match.homeTeamID {
                home += value
            } else if event.teamID == match.awayTeamID {
                away += value
            }
            map[event.id] = (home, away)
        }
        return map
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            summaryBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 8) {
                        topBar
                        scoreHeaderCard
                        scopePicker
                        possessionCard
                        HStack(alignment: .top, spacing: 10) {
                            scoringBreakdownCard
                                .frame(maxWidth: .infinity)
                                .layoutPriority(1)
                            setPieceCard
                                .frame(maxWidth: .infinity)
                        }
                        scorerTimelineCard
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 16)
                }
                .simultaneousGesture(scopeSwipeGesture)

                csvExportBar
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isRecordingPresented) {
            V3RecordingView(match: match)
        }
        .fullScreenCover(isPresented: $isTimelineEditorPresented) {
            TimelineEditorView(match: match)
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

    // MARK: - Main layout

    private var summaryBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.01, green: 0.04, blue: 0.08),
                Color(red: 0.03, green: 0.08, blue: 0.13),
                Color(red: 0.01, green: 0.03, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topBar: some View {
        ZStack {
            Text("サマリー")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        isTimelineEditorPresented = true
                    } label: {
                        Text("編集")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 54, height: 44)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        isRecordingPresented = true
                    } label: {
                        Text("記録へ")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 64, height: 44)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 50)
    }

    // 画面最下部に固定するCSV出力ボタン(得点タイムラインの枠の外)
    private var csvExportBar: some View {
        ShareLink(item: csvFile, preview: SharePreview(csvFile.fileName)) {
            Label("CSV出力", systemImage: "square.and.arrow.down")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.38), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("CSVで書き出し")
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var scoreHeaderCard: some View {
        VStack(spacing: 9) {
            if isFinished {
                Text("試合終了")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.22))
                    .clipShape(Capsule())
            }

            HStack(alignment: .center, spacing: 8) {
                teamColumn(teamID: match.homeTeamID, label: "HOME", accent: homeAccent)

                Text("\(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID))")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity)

                teamColumn(teamID: match.awayTeamID, label: "AWAY", accent: awayAccent)
            }

            HStack(spacing: 16) {
                halfScoreText("前半", half: 0)
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: 18)
                halfScoreText("後半", half: 1)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.white.opacity(0.56))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .summaryCard()
    }

    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(SummaryScope.allCases) { scope in
                Button {
                    selectedScope = scope
                } label: {
                    Text(scope.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selectedScope == scope ? .white : .white.opacity(0.46))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background {
                            if selectedScope == scope {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.blue.opacity(0.58))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.blue.opacity(0.92), lineWidth: 1.5)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.07))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    private func teamColumn(teamID: UUID, label: String, accent: Color) -> some View {
        VStack(spacing: 6) {
            teamLogoBox(teamID: teamID, size: 58)
            Text(teamName(for: teamID))
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(accent.opacity(0.25))
                .clipShape(Capsule())
        }
        .frame(width: 88)
    }

    @ViewBuilder
    private func teamLogoBox(teamID: UUID, size: CGFloat) -> some View {
        let team = teams.first { $0.id == teamID }
        Group {
            if let team, let name = team.logoPath, let uiImage = ImageStorage.image(named: name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private func halfScoreText(_ title: String, half: Int) -> some View {
        Text("\(title) \(score(for: match.homeTeamID, half: half))-\(score(for: match.awayTeamID, half: half))")
    }

    private func teamPill(_ title: String, accent: Color) -> some View {
        Text(title)
            .font(.caption.weight(.black))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(accent.opacity(0.22))
            .clipShape(Capsule())
    }

    // MARK: - Possession

    private var possessionCard: some View {
        let half = selectedScope.half
        let homeSeconds = possessionSeconds(teamID: match.homeTeamID, half: half)
        let awaySeconds = possessionSeconds(teamID: match.awayTeamID, half: half)
        let bipSeconds = bipTotalSeconds(homeSeconds: homeSeconds, awaySeconds: awaySeconds, half: half)
        let teamsTotal = homeSeconds + awaySeconds
        let homeRatio = teamsTotal == 0 ? 0 : Double(homeSeconds) / Double(teamsTotal)
        let awayRatio = teamsTotal == 0 ? 0 : Double(awaySeconds) / Double(teamsTotal)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ポゼッション")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Text("BIP \(timeText(bipSeconds))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.56))
                Image(systemName: "info.circle")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
            }

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(homeAccent)
                        .frame(width: max(0, proxy.size.width * homeRatio))
                    Rectangle()
                        .fill(awayAccent)
                        .frame(width: max(0, proxy.size.width * awayRatio))
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(percentText(homeRatio))
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(homeAccent)
                    HStack(spacing: 8) {
                        Text(timeText(homeSeconds))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                        teamPill("HOME", accent: homeAccent)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(percentText(awayRatio))
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(awayAccent)
                    HStack(spacing: 8) {
                        teamPill("AWAY", accent: awayAccent)
                        Text(timeText(awaySeconds))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
        .padding(14)
        .summaryCard()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scoring breakdown

    private var scoringBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("得点内訳", systemImage: "list.bullet.rectangle")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .labelStyle(.titleAndIcon)

            HStack {
                Text("HOME")
                    .font(.caption.weight(.black))
                    .foregroundStyle(homeAccent)
                Spacer()
                Text("AWAY")
                    .font(.caption.weight(.black))
                    .foregroundStyle(awayAccent)
            }

            scoringBreakdownRow(.tryScore, symbol: "rugbyball")
            scoringBreakdownRow(.conversion, symbol: "figure.rugby")
            scoringBreakdownRow(.penaltyGoal, symbol: "p.circle")
            scoringBreakdownRow(.dropGoal, symbol: "d.circle")

            Divider()
                .overlay(Color.white.opacity(0.18))

            HStack {
                Text("\(score(for: match.homeTeamID, half: selectedScope.half))")
                    .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(homeAccent)
                    .frame(width: 48, alignment: .leading)
                Spacer()
                Text("合計")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer()
                Text("\(score(for: match.awayTeamID, half: selectedScope.half))")
                    .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(awayAccent)
                    .frame(width: 48, alignment: .trailing)
            }
        }
        .padding(12)
        .summaryCard()
        .frame(maxWidth: .infinity)
    }

    private func scoringBreakdownRow(_ category: ScoringCategory, symbol: String) -> some View {
        let homeCount = countScoring(category, teamID: match.homeTeamID, half: selectedScope.half)
        let awayCount = countScoring(category, teamID: match.awayTeamID, half: selectedScope.half)

        return HStack(spacing: 6) {
            Text("\(homeCount)")
                .font(.headline.weight(.black).monospacedDigit())
                .foregroundStyle(homeAccent)
                .frame(width: 26, alignment: .leading)
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                Text(category.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity)
            Text("\(awayCount)")
                .font(.headline.weight(.black).monospacedDigit())
                .foregroundStyle(awayAccent)
                .frame(width: 26, alignment: .trailing)
        }
    }

    // MARK: - Set piece

    private var setPieceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("セットプレー", systemImage: "figure.rugby")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)

            setPieceRow(title: "ラインアウト", category: "lineout", symbol: "figure.rugby")

            Divider()
                .overlay(Color.white.opacity(0.18))

            setPieceRow(title: "スクラム", category: "scrum", symbol: "circle.grid.cross")
        }
        .padding(12)
        .summaryCard()
        .frame(maxWidth: .infinity)
    }

    private func setPieceRow(title: String, category: String, symbol: String) -> some View {
        let home = setPieceStats(category: category, teamID: match.homeTeamID, half: selectedScope.half)
        let away = setPieceStats(category: category, teamID: match.awayTeamID, half: selectedScope.half)

        return VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.black))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                setPieceGauge(rate: home.rate, accent: homeAccent, success: home.success, total: home.total)
                    .frame(width: 58, height: 58)
                Spacer()
                Image(systemName: symbol)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.52))
                Spacer()
                setPieceGauge(rate: away.rate, accent: awayAccent, success: away.success, total: away.total)
                    .frame(width: 58, height: 58)
            }
        }
    }

    private func setPieceGauge(rate: Double, accent: Color, success: Int, total: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 7)
            if total > 0 {
                Circle()
                    .trim(from: 0, to: max(0.001, rate))
                    .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(percentText(rate))
                    .font(.caption.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
                Text("\(success)/\(total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    // MARK: - Scorer timeline

    private var scorerTimelineCard: some View {
        let visibleEvents = scoringEventsForSelectedScope

        return VStack(alignment: .leading, spacing: 12) {
            Label("得点タイムライン（\(selectedScope.title)）", systemImage: "clock")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)

            Divider()
                .overlay(Color.white.opacity(0.18))

            if visibleEvents.isEmpty {
                Text("得点記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                let progression = scoringProgression
                if selectedScope.half != nil {
                    ForEach(visibleEvents) { event in
                        scorerRow(event, progression: progression[event.id] ?? (0, 0))
                    }
                } else {
                    ForEach([0, 1], id: \.self) { half in
                        let halfEvents = visibleEvents.filter { $0.half == half }
                        if !halfEvents.isEmpty {
                            halfHeaderRow(half)
                            ForEach(halfEvents) { event in
                                scorerRow(event, progression: progression[event.id] ?? (0, 0))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .summaryCard()
        .frame(maxWidth: .infinity)
    }

    private func halfHeaderRow(_ half: Int) -> some View {
        HStack(spacing: 8) {
            Text(halfLabel(half))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
        }
    }

    private func scorerRow(_ event: StatEvent, progression: (home: Int, away: Int)) -> some View {
        let teamAccent: Color = event.teamID == match.homeTeamID ? homeAccent
            : event.teamID == match.awayTeamID ? awayAccent
            : .secondary

        return Button {
            scoringEventForPlayerSelection = event
        } label: {
            HStack(spacing: 8) {
                Text(timeText(event.seconds))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 46, alignment: .leading)

                Text(categoryTag(event.category))
                    .font(.callout.weight(.black))
                    .frame(width: 46)
                    .padding(.vertical, 6)
                    .background(categoryColor(event.category).opacity(0.18))
                    .foregroundStyle(categoryColor(event.category))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                playerAvatar(playerID: event.playerID, accent: teamAccent, size: 30)

                Text(playerName(for: event.playerID))
                    .font(.headline)
                    .foregroundStyle(event.playerID == nil ? .orange : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 4)

                Text("\(progression.home) - \(progression.away)")
                    .font(.headline.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                deleteEvent(event)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func playerAvatar(playerID: UUID?, accent: Color, size: CGFloat) -> some View {
        let player = playerID.flatMap { id in players.first { $0.id == id } }
        ZStack {
            if let player,
               let imagePath = player.imagePath,
               let uiImage = ImageStorage.image(named: imagePath) {
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            }
            Circle()
                .stroke(accent.opacity(0.5), lineWidth: 1.5)
                .frame(width: size, height: size)
        }
    }

    // MARK: - Calculations

    private func score(for teamID: UUID, half: Int? = nil) -> Int {
        scoringEvents
            .filter { event in
                event.teamID == teamID && (half == nil || event.half == half)
            }
            .reduce(0) { $0 + scoreValue(for: $1) }
    }

    private var scoringEventsForSelectedScope: [StatEvent] {
        guard let half = selectedScope.half else { return scoringEvents }
        return scoringEvents.filter { $0.half == half }
    }

    private func countScoring(_ category: ScoringCategory, teamID: UUID, half: Int? = nil) -> Int {
        scoringEvents
            .filter { event in
                event.category == category.rawValue
                    && event.teamID == teamID
                    && (half == nil || event.half == half)
            }
            .count
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

    private func possessionSeconds(teamID: UUID, half: Int? = nil) -> Int {
        let events = possessionEvents.filter { half == nil || $0.half == half }
        let teamOwnedSeconds = events
            .filter { $0.teamID == teamID }
            .reduce(0) { $0 + $1.seconds }
        if teamOwnedSeconds > 0 { return teamOwnedSeconds }

        if teamID == match.homeTeamID {
            return events
                .filter { $0.teamID == nil && $0.outcome == "own" }
                .reduce(0) { $0 + $1.seconds }
        }
        return events
            .filter { $0.teamID == nil && $0.outcome == "opponent" }
            .reduce(0) { $0 + $1.seconds }
    }

    private func bipTotalSeconds(homeSeconds: Int, awaySeconds: Int, half: Int? = nil) -> Int {
        let recordedBIPSeconds = possessionEvents
            .filter { half == nil || $0.half == half }
            .filter { $0.outcome == "none" }
            .reduce(0) { $0 + $1.seconds }
        if recordedBIPSeconds > 0 { return recordedBIPSeconds }
        return homeSeconds + awaySeconds
    }

    private func setPieceStats(category: String, teamID: UUID, half: Int? = nil) -> (success: Int, total: Int, rate: Double) {
        let events = setPieceEvents.filter { event in
            event.category == category
                && event.teamID == teamID
                && (half == nil || event.half == half)
        }
        let success = events.filter { $0.outcome == "success" }.count
        let total = events.count
        return (success, total, total == 0 ? 0 : Double(success) / Double(total))
    }

    // MARK: - Formatters

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
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

    private func categoryTag(_ category: String) -> String {
        switch ScoringCategory(rawValue: category) {
        case .tryScore: return "TRY"
        case .conversion: return "CON"
        case .penaltyGoal: return "PG"
        case .dropGoal: return "DG"
        case nil: return category.uppercased()
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch ScoringCategory(rawValue: category) {
        case .tryScore: return .green
        case .conversion: return .purple
        case .penaltyGoal: return .blue
        case .dropGoal: return .orange
        case nil: return .secondary
        }
    }

    private func moveScope(forward: Bool) {
        let scopes = SummaryScope.allCases
        guard let currentIndex = scopes.firstIndex(of: selectedScope) else { return }
        let nextIndex = forward
            ? min(currentIndex + 1, scopes.count - 1)
            : max(currentIndex - 1, 0)
        guard nextIndex != currentIndex else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            selectedScope = scopes[nextIndex]
        }
    }

    private func deleteEvent(_ event: StatEvent) {
        modelContext.delete(event)
        try? modelContext.save()
    }
}

private extension View {
    func summaryCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.075))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(red: 0.04, green: 0.08, blue: 0.13).opacity(0.78))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
        MatchLineup.self,
        Substitution.self
    ], inMemory: true)
}
