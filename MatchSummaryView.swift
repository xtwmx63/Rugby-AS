//
//  MatchSummaryView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import SwiftData
import SwiftUI
import UIKit

struct MatchSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query private var matchEvents: [StatEvent]
    @Query private var teams: [Team]
    @Query private var tournaments: [Tournament]
    @Query private var allSubstitutions: [Substitution]

    let match: Match

    @State private var scoringEventForPlayerSelection: StatEvent?
    @State private var isRecordingPresented = false
    @State private var isTimelineEditorPresented = false
    @State private var selectedScope: SummaryScope = .all
    // 得点経過チャートで選択中の得点(タップで吹き出し表示)
    @State private var selectedProgressionEventID: UUID?
    // 得点差グラフの視点。nil なら自動(最終勝者、同点はHOME)
    @State private var marginPerspectiveOverride: Bool?
    // 「画像で共有」で生成したサマリー画像(セット中はプレビューシートを表示)
    @State private var exportedSummaryImage: UIImage?
    // 交代の追加シート
    @State private var isSubstitutionSheetPresented = false

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
                    VStack(spacing: 6) {
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
                        scoringProgressionCard
                        scoreMarginCard
                        scorerTimelineCard
                        substitutionCard
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
        .onChange(of: selectedScope) { _, _ in
            selectedProgressionEventID = nil
        }
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
        .sheet(isPresented: Binding(
            get: { exportedSummaryImage != nil },
            set: { if !$0 { exportedSummaryImage = nil } }
        )) {
            if let exportedSummaryImage {
                SummaryImageShareSheet(image: exportedSummaryImage, title: summaryImageTitle)
            }
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

    // 画面最下部に固定する書き出しバー(CSVと画像。得点タイムラインの枠の外)
    private var csvExportBar: some View {
        HStack(spacing: 10) {
            ShareLink(item: csvFile, preview: SharePreview(csvFile.fileName)) {
                exportBarLabel("CSV出力", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("CSVで書き出し")

            Button {
                renderSummaryImage()
            } label: {
                exportBarLabel("画像で共有", systemImage: "photo")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("サマリーを画像で共有")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func exportBarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.38), lineWidth: 1.5)
            )
    }

    // MARK: - サマリーの画像書き出し

    private var summaryImageTitle: String {
        "\(teamName(for: match.homeTeamID)) vs \(teamName(for: match.awayTeamID)) サマリー"
    }

    // 画像として書き出す中身(画面のカードをそのまま並べ、下にクレジットを足す)
    private var summaryImageContent: some View {
        VStack(spacing: 8) {
            scoreHeaderCard
            possessionCard
            HStack(alignment: .top, spacing: 10) {
                scoringBreakdownCard
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                setPieceCard
                    .frame(maxWidth: .infinity)
            }
            scoringProgressionCard
            scoreMarginCard
            scorerTimelineCard

            HStack {
                Text(tournaments.first { $0.id == match.tournamentID }?.officialName ?? "")
                    .lineLimit(1)
                Spacer()
                Text("Rugby AS")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(summaryBackground)
        .environment(\.colorScheme, .dark)
        .frame(width: 420)
    }

    // 画面の内容を1枚の画像にする(3倍解像度で鮮明に)
    @MainActor
    private func renderSummaryImage() {
        let renderer = ImageRenderer(content: summaryImageContent)
        renderer.scale = 3
        exportedSummaryImage = renderer.uiImage
    }

    private var scoreHeaderCard: some View {
        VStack(spacing: 6) {
            if isFinished {
                Text("試合終了")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.22))
                    .clipShape(Capsule())
            }

            HStack(alignment: .center, spacing: 8) {
                teamColumn(teamID: match.homeTeamID, label: "HOME", accent: homeAccent)

                Text("\(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID))")
                    .font(.system(size: 34, weight: .black, design: .rounded))
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
        .padding(.vertical, 9)
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
        VStack(spacing: 5) {
            teamLogoBox(teamID: teamID, size: 48)
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

        return VStack(alignment: .leading, spacing: 9) {
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
            .frame(height: 12)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(percentText(homeRatio))
                        .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
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
                        .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
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
        .padding(10)
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

    // MARK: - 得点経過チャート

    // チャートに置く1つの得点マーカー
    private struct ProgressionMarker: Identifiable {
        let id: UUID
        let axisSeconds: Double
        let isHome: Bool
        let letter: String
        let event: StatEvent
    }

    // その前後半の軸の長さ(秒)。実際の記録の最終時刻を分単位に切り上げる。
    // 形式(7人制/15人制)を決め打ちしないため、データから長さを決める。
    private func halfAxisSeconds(_ half: Int) -> Double {
        let maxEventSecond = matchEvents
            .filter { $0.half == half && $0.category != "match_state" }
            .map { event -> Int in
                if event.category == "possession" {
                    return (event.startSeconds ?? 0) + event.seconds
                }
                return event.seconds
            }
            .max() ?? 0
        return Double(max(60, Int(ceil(Double(maxEventSecond) / 60.0)) * 60))
    }

    // 表示スコープに応じた軸全体の長さと、HT(ハーフタイム)の位置
    private var progressionAxis: (total: Double, halftime: Double?) {
        if let half = selectedScope.half {
            return (halfAxisSeconds(half), nil)
        }
        let firstHalf = halfAxisSeconds(0)
        return (firstHalf + halfAxisSeconds(1), firstHalf)
    }

    private var progressionMarkers: [ProgressionMarker] {
        let firstHalfSeconds = halfAxisSeconds(0)
        return scoringEventsForSelectedScope
            // 成功した得点だけをチャートに置く(失敗したCON/PG/DGは表示しない)
            .filter { $0.outcome == "success" }
            .filter { $0.teamID == match.homeTeamID || $0.teamID == match.awayTeamID }
            .map { event in
                let base = (selectedScope.half == nil && event.half >= 1) ? firstHalfSeconds : 0
                return ProgressionMarker(
                    id: event.id,
                    axisSeconds: base + Double(event.seconds),
                    isHome: event.teamID == match.homeTeamID,
                    letter: progressionLetter(event.category),
                    event: event
                )
            }
    }

    private func progressionLetter(_ category: String) -> String {
        switch category {
        case "try": return "T"
        case "conversion": return "C"
        case "penalty_goal": return "P"
        case "drop_goal": return "D"
        default: return "?"
        }
    }

    // 分表示の間隔。数字だらけにならないよう、試合の長さに合わせて
    // 1/2/5/10/20分刻みから「9個以内に収まる」ものを選ぶ。
    private func progressionTickSeconds(total: Double) -> Double {
        let totalMinutes = total / 60.0
        for minutes in [1.0, 2.0, 5.0, 10.0, 20.0] where totalMinutes / minutes <= 9 {
            return minutes * 60
        }
        return 30 * 60
    }

    private func progressionTimeLabel(for event: StatEvent) -> String {
        if selectedScope.half == nil {
            return "\(halfLabel(event.half)) \(timeText(event.seconds))"
        }
        return timeText(event.seconds)
    }

    private var scoringProgressionCard: some View {
        let axis = progressionAxis
        let markers = progressionMarkers

        return VStack(alignment: .leading, spacing: 8) {
            Label("得点経過（\(selectedScope.title)）", systemImage: "chart.xyaxis.line")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)

            if markers.isEmpty {
                Text("得点記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                progressionChart(markers: markers, axisTotal: axis.total, halftime: axis.halftime)
            }
        }
        .padding(12)
        .summaryCard()
        .frame(maxWidth: .infinity)
    }

    private func progressionChart(
        markers: [ProgressionMarker],
        axisTotal: Double,
        halftime: Double?
    ) -> some View {
        // 上から: 吹き出しエリア / HOME行 / 分表示 / AWAY行 / HT表示
        let bubbleHeight: CGFloat = 50
        let rowHeight: CGFloat = 30
        let tickHeight: CGFloat = 16
        let halftimeLabelHeight: CGFloat = halftime == nil ? 0 : 14
        let chartHeight = bubbleHeight + rowHeight * 2 + tickHeight + halftimeLabelHeight
        let tickStep = progressionTickSeconds(total: axisTotal)

        return GeometryReader { geo in
            let labelWidth: CGFloat = 44
            let plotLeft = labelWidth + 12
            let plotRight = max(plotLeft + 1, geo.size.width - 14)
            let yHome = bubbleHeight + rowHeight / 2
            let yTicks = bubbleHeight + rowHeight + tickHeight / 2
            let yAway = bubbleHeight + rowHeight + tickHeight + rowHeight / 2
            let xPosition: (Double) -> CGFloat = { seconds in
                plotLeft + CGFloat(seconds / max(axisTotal, 1)) * (plotRight - plotLeft)
            }

            ZStack(alignment: .topLeading) {
                // 行ラベルと下敷きの線
                Text("HOME")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(homeAccent)
                    .position(x: labelWidth / 2, y: yHome)
                Text("AWAY")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(awayAccent)
                    .position(x: labelWidth / 2, y: yAway)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: plotRight - plotLeft, height: 1)
                    .position(x: (plotLeft + plotRight) / 2, y: yHome)
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: plotRight - plotLeft, height: 1)
                    .position(x: (plotLeft + plotRight) / 2, y: yAway)

                // 分表示(間引き済み)。全体表示では後半も0分から振り直す
                let ticks: [(x: Double, minutes: Int)] = {
                    guard let halftime else {
                        return stride(from: 0.0, through: axisTotal, by: tickStep)
                            .map { ($0, Int($0) / 60) }
                    }
                    var result: [(Double, Int)] = stride(from: 0.0, through: halftime, by: tickStep)
                        .map { ($0, Int($0) / 60) }
                    // 後半分。0分はHTの線と重なるので省く
                    let secondHalfTotal = axisTotal - halftime
                    result += stride(from: tickStep, through: secondHalfTotal, by: tickStep)
                        .map { (halftime + $0, Int($0) / 60) }
                    return result
                }()

                ForEach(ticks, id: \.x) { tick in
                    Text("\(tick.minutes)'")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                        .position(x: xPosition(tick.x), y: yTicks)
                }

                // ハーフタイムの区切り(全体表示のみ)
                if let halftime {
                    VerticalDashedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .frame(width: 1, height: yAway - yHome + rowHeight)
                        .position(x: xPosition(halftime), y: (yHome + yAway) / 2)

                    Text("HT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .position(x: xPosition(halftime), y: yAway + rowHeight / 2 + 7)
                }

                // 得点マーカー(タップで吹き出し)
                ForEach(markers) { marker in
                    let accent = marker.isHome ? homeAccent : awayAccent
                    let isSelected = selectedProgressionEventID == marker.id
                    // CONはTryとほぼ同時刻で重なるので、行の外側
                    // (HOMEは上・AWAYは下)へ少しずらし、小さめにしてペアで見せる
                    let isConversion = marker.event.category == "conversion"
                    let rowY = marker.isHome ? yHome : yAway
                    let markerY = isConversion ? (marker.isHome ? rowY - 12 : rowY + 12) : rowY
                    let markerSize: CGFloat = isConversion ? 19 : 22

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedProgressionEventID = isSelected ? nil : marker.id
                        }
                    } label: {
                        Text(marker.letter)
                            .font(.system(size: isConversion ? 10 : 11, weight: .black, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(width: markerSize, height: markerSize)
                            .background(Circle().fill(accent))
                            .overlay(
                                Circle().stroke(
                                    isSelected ? Color.white : Color.black.opacity(0.35),
                                    lineWidth: isSelected ? 2 : 1
                                )
                            )
                            .scaleEffect(isSelected ? 1.15 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .position(x: xPosition(marker.axisSeconds), y: markerY)
                    .zIndex(isSelected ? 2 : 1)
                }

                // 選択中の得点の詳細(種類・秒までの時間・選手)
                if let selected = markers.first(where: { $0.id == selectedProgressionEventID }) {
                    let accent = selected.isHome ? homeAccent : awayAccent
                    let bubbleX = min(max(xPosition(selected.axisSeconds), 92), geo.size.width - 92)

                    HStack(spacing: 8) {
                        playerAvatar(playerID: selected.event.playerID, accent: accent, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(categoryTag(selected.event.category))
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(accent)
                                Text(progressionTimeLabel(for: selected.event))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                            Text(playerName(for: selected.event.playerID))
                                .font(.caption)
                                .foregroundStyle(selected.event.playerID == nil ? .orange : .white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.05, green: 0.10, blue: 0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .position(x: bubbleX, y: bubbleHeight / 2)
                }
            }
        }
        .frame(height: chartHeight)
    }

    // MARK: - 得点差の推移グラフ

    // グラフの視点。手動で切り替えた場合はそれを優先し、
    // 未指定なら最終勝利チーム(同点ならHOME)。
    private var marginPerspectiveIsHome: Bool {
        marginPerspectiveOverride ?? (score(for: match.homeTeamID) >= score(for: match.awayTeamID))
    }

    // イベントのチャート上の時刻(全体表示では後半に前半の長さを足す)
    private func marginAxisSeconds(for event: StatEvent) -> Double {
        let base = (selectedScope.half == nil && event.half >= 1) ? halfAxisSeconds(0) : 0
        return base + Double(event.seconds)
    }

    // 得点差が変化した点のリスト(時刻順・累積済み)。
    // 成功したCONは対になるTRYの時刻にまとめて、TRY+CON=7点を一度に動かす。
    private func marginSteps() -> [(axisSeconds: Double, margin: Int)] {
        let events = scoringEventsForSelectedScope.filter { event in
            event.outcome == "success"
                && (event.teamID == match.homeTeamID || event.teamID == match.awayTeamID)
        }
        let tries = events.filter { $0.category == "try" }
        let perspectiveSign = marginPerspectiveIsHome ? 1 : -1

        var deltas: [(time: Double, delta: Int)] = events.map { event in
            let teamSign = event.teamID == match.homeTeamID ? 1 : -1
            var time = marginAxisSeconds(for: event)
            // 成功CONは同じチーム・同じハーフで直前のTRYの時刻に寄せる
            if event.category == "conversion" {
                let pairedTry = tries
                    .filter { $0.teamID == event.teamID && $0.half == event.half && $0.seconds <= event.seconds }
                    .max { $0.seconds < $1.seconds }
                if let pairedTry {
                    time = marginAxisSeconds(for: pairedTry)
                }
            }
            return (time, perspectiveSign * teamSign * scoreValue(for: event))
        }
        deltas.sort { $0.time < $1.time }

        // 同じ時刻の変化(TRY+CON)は1つの点にまとめて累積していく
        var steps: [(axisSeconds: Double, margin: Int)] = []
        var margin = marginAtScopeStart()
        for delta in deltas {
            margin += delta.delta
            if let last = steps.last, abs(last.axisSeconds - delta.time) < 0.5 {
                steps[steps.count - 1].margin = margin
            } else {
                steps.append((delta.time, margin))
            }
        }
        return steps
    }

    // スコープ開始時点の得点差(後半表示のときは前半終了時の差から始める)
    private func marginAtScopeStart() -> Int {
        guard selectedScope.half == 1 else { return 0 }
        let firstHalfMargin = score(for: match.homeTeamID, half: 0) - score(for: match.awayTeamID, half: 0)
        return marginPerspectiveIsHome ? firstHalfMargin : -firstHalfMargin
    }

    // 視点切り替え(HOME/AWAY)のチップ
    private func marginPerspectiveChip(_ title: String, isHome: Bool) -> some View {
        let isSelected = marginPerspectiveIsHome == isHome
        let accent = isHome ? homeAccent : awayAccent

        return Button {
            marginPerspectiveOverride = isHome
        } label: {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? accent.opacity(0.42) : Color.white.opacity(0.07)))
                .overlay(
                    Capsule().stroke(
                        isSelected ? accent : Color.white.opacity(0.14),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var scoreMarginCard: some View {
        let axis = progressionAxis
        let steps = marginSteps()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("得点差の推移（\(selectedScope.title)）", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                HStack(spacing: 4) {
                    marginPerspectiveChip("HOME", isHome: true)
                    marginPerspectiveChip("AWAY", isHome: false)
                }
            }

            if steps.isEmpty && marginAtScopeStart() == 0 {
                Text("得点記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                marginChart(steps: steps, axisTotal: axis.total, halftime: axis.halftime)
            }
        }
        .padding(12)
        .summaryCard()
        .frame(maxWidth: .infinity)
    }

    private func marginChart(
        steps: [(axisSeconds: Double, margin: Int)],
        axisTotal: Double,
        halftime: Double?
    ) -> some View {
        let plotHeight: CGFloat = 110
        let tickHeight: CGFloat = 16
        let halftimeLabelHeight: CGFloat = halftime == nil ? 0 : 14
        let chartHeight = plotHeight + tickHeight + halftimeLabelHeight
        let tickStep = progressionTickSeconds(total: axisTotal)
        let startMargin = marginAtScopeStart()
        let accent = marginPerspectiveIsHome ? homeAccent : awayAccent

        // 縦軸の範囲。0を必ず含め、7点(トライ+ゴール)単位で切り上げる
        let margins = [startMargin] + steps.map(\.margin)
        let maxMargin = max(7, Int(ceil(Double(margins.max() ?? 0) / 7.0)) * 7)
        let minMargin = min(0, Int(floor(Double(margins.min() ?? 0) / 7.0)) * 7)
        // 7点ごとの目盛り線の値
        let gridValues = Array(stride(from: minMargin, through: maxMargin, by: 7))

        return GeometryReader { geo in
            let labelWidth: CGFloat = 34
            let plotLeft = labelWidth + 8
            let plotRight = max(plotLeft + 1, geo.size.width - 14)
            let yTicks = plotHeight + tickHeight / 2
            let xPosition: (Double) -> CGFloat = { seconds in
                plotLeft + CGFloat(seconds / max(axisTotal, 1)) * (plotRight - plotLeft)
            }
            let yPosition: (Int) -> CGFloat = { margin in
                let range = CGFloat(max(maxMargin - minMargin, 1))
                return (CGFloat(maxMargin - margin) / range) * (plotHeight - 12) + 6
            }

            ZStack(alignment: .topLeading) {
                // 7点ごとの目盛り線(0の線だけ濃くする)
                ForEach(gridValues, id: \.self) { value in
                    Rectangle()
                        .fill(Color.white.opacity(value == 0 ? 0.28 : 0.10))
                        .frame(width: plotRight - plotLeft, height: 1)
                        .position(x: (plotLeft + plotRight) / 2, y: yPosition(value))
                    Text(value > 0 ? "+\(value)" : "\(value)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(value == 0 ? 0.6 : 0.4))
                        .position(x: labelWidth / 2, y: yPosition(value))
                }

                // 分表示(得点経過と同じ振り方)
                let ticks: [(x: Double, minutes: Int)] = {
                    guard let halftime else {
                        return stride(from: 0.0, through: axisTotal, by: tickStep)
                            .map { ($0, Int($0) / 60) }
                    }
                    var result: [(Double, Int)] = stride(from: 0.0, through: halftime, by: tickStep)
                        .map { ($0, Int($0) / 60) }
                    let secondHalfTotal = axisTotal - halftime
                    result += stride(from: tickStep, through: secondHalfTotal, by: tickStep)
                        .map { (halftime + $0, Int($0) / 60) }
                    return result
                }()

                ForEach(ticks, id: \.x) { tick in
                    Text("\(tick.minutes)'")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                        .position(x: xPosition(tick.x), y: yTicks)
                }

                // ハーフタイムの区切り(全体表示のみ)
                if let halftime {
                    VerticalDashedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .frame(width: 1, height: plotHeight)
                        .position(x: xPosition(halftime), y: plotHeight / 2)

                    Text("HT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .position(x: xPosition(halftime), y: plotHeight + tickHeight + 7)
                }

                // 得点差の階段状の折れ線
                Path { path in
                    var currentMargin = startMargin
                    path.move(to: CGPoint(x: plotLeft, y: yPosition(currentMargin)))
                    for step in steps {
                        let x = xPosition(step.axisSeconds)
                        path.addLine(to: CGPoint(x: x, y: yPosition(currentMargin)))
                        path.addLine(to: CGPoint(x: x, y: yPosition(step.margin)))
                        currentMargin = step.margin
                    }
                    path.addLine(to: CGPoint(x: plotRight, y: yPosition(currentMargin)))
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))

                // 得点が動いたポイントに小さいマーカーを置く
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1))
                        .position(x: xPosition(step.axisSeconds), y: yPosition(step.margin))
                }

                // 最終的な得点差を線の終わりに表示
                if let finalMargin = steps.last?.margin ?? (startMargin != 0 ? startMargin : nil) {
                    Text(finalMargin > 0 ? "+\(finalMargin)" : "\(finalMargin)")
                        .font(.caption.weight(.black).monospacedDigit())
                        .foregroundStyle(accent)
                        .position(
                            x: plotRight - 12,
                            y: max(12, yPosition(finalMargin) - 12)
                        )
                }
            }
        }
        .frame(height: chartHeight)
    }

    // MARK: - 交代カード

    private var matchSubstitutions: [Substitution] {
        allSubstitutions
            .filter { $0.matchID == match.id }
            .sorted { ($0.half, $0.minute) < ($1.half, $1.minute) }
    }

    private var substitutionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("交代", systemImage: "arrow.left.arrow.right")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    isSubstitutionSheetPresented = true
                } label: {
                    Label("追加", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.blue.opacity(0.72))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Divider()
                .overlay(Color.white.opacity(0.18))

            if matchSubstitutions.isEmpty {
                Text("交代の記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(matchSubstitutions) { substitution in
                    substitutionRow(substitution)
                }
            }
        }
        .padding(12)
        .summaryCard()
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $isSubstitutionSheetPresented) {
            SubstitutionAddSheet(
                match: match,
                teams: teams,
                players: players,
                initialHalf: selectedScope.half ?? 0,
                initialMinute: 0,
                onAdd: { playerOutID, playerInID, half, minute in
                    let substitution = Substitution(
                        matchID: match.id,
                        playerInID: playerInID,
                        playerOutID: playerOutID,
                        minute: minute,
                        half: half
                    )
                    modelContext.insert(substitution)
                    try? modelContext.save()
                }
            )
            .presentationDetents([.large])
        }
    }

    private func substitutionRow(_ substitution: Substitution) -> some View {
        HStack(spacing: 8) {
            Text("\(halfLabel(substitution.half)) \(substitution.minute)'")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 64, alignment: .leading)

            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.red)
            Text(playerName(for: substitution.playerOutID))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.4))

            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.green)
            Text(playerName(for: substitution.playerInID))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            Button {
                modelContext.delete(substitution)
                try? modelContext.save()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }

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
        // 失敗したキック(CON/PG/DG)はチップを薄くして✕印を付ける
        let isFailed = event.outcome == "fail"

        return Button {
            scoringEventForPlayerSelection = event
        } label: {
            HStack(spacing: 8) {
                // 失敗した行は✕バッジ以外を全体的に薄くして、成功行と一目で区別する
                Text(timeText(event.seconds))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 46, alignment: .leading)
                    .opacity(isFailed ? 0.45 : 1.0)

                Text(categoryTag(event.category))
                    .font(.callout.weight(.black))
                    .frame(width: 46)
                    .padding(.vertical, 6)
                    .background(categoryColor(event.category).opacity(isFailed ? 0.08 : 0.18))
                    .foregroundStyle(categoryColor(event.category).opacity(isFailed ? 0.45 : 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(alignment: .topTrailing) {
                        if isFailed {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.orange)
                                .background(Circle().fill(Color(red: 0.03, green: 0.07, blue: 0.12)))
                                .offset(x: 5, y: -5)
                        }
                    }

                playerAvatar(playerID: event.playerID, accent: teamAccent, size: 30)
                    .opacity(isFailed ? 0.45 : 1.0)

                Text(playerName(for: event.playerID))
                    .font(.headline)
                    .foregroundStyle(event.playerID == nil ? .orange : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(isFailed ? 0.45 : 1.0)

                Spacer(minLength: 4)

                Text("\(progression.home) - \(progression.away)")
                    .font(.headline.weight(.black).monospacedDigit())
                    .foregroundStyle(.white)
                    .opacity(isFailed ? 0.45 : 1.0)
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

// 生成したサマリー画像のプレビューと共有
private struct SummaryImageShareSheet: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("画像で共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview(title, image: Image(uiImage: image))
                    )
                }
            }
        }
    }
}

// 得点経過チャートのHT(ハーフタイム)区切りに使う縦の点線
private struct VerticalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
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
