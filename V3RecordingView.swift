//
//  V3RecordingView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/18.
//

import SwiftData
import SwiftUI
import UIKit

struct V3RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var teams: [Team]
    // 全選手を取って main thread でソートするのは初回 push 時に体感ラグを生むので、
    // 当該試合に出てくる 2 チームの選手だけに絞る。
    @Query private var allPlayers: [Player]
    // body 内で毎回 allEvents を filter するのは重いので、Query 段階で
    // 当該 match のイベントだけに絞る。
    @Query private var matchEvents: [StatEvent]
    // 試合前に登録したスタメン/リザーブ。選手選択時の並び順だけに使う。
    @Query private var matchLineupEntries: [MatchLineup]

    let match: Match

    init(match: Match) {
        self.match = match
        let matchID = match.id
        let homeID = match.homeTeamID
        let awayID = match.awayTeamID
        _matchEvents = Query(filter: #Predicate<StatEvent> { event in
            event.matchID == matchID
        })
        _matchLineupEntries = Query(filter: #Predicate<MatchLineup> { entry in
            entry.matchID == matchID
        })
        _allPlayers = Query(
            filter: #Predicate<Player> { player in
                player.teamID == homeID || player.teamID == awayID
            },
            sort: [SortDescriptor(\Player.number)]
        )
    }

    @State private var timeState = V3TimerState()
    @State private var bipState = V3TimerState()
    @State private var team1State = V3TimerState()
    @State private var team2State = V3TimerState()
    @State private var selectedInputTeamID: UUID?
    @State private var scoringEventForPlayerSelection: StatEvent?
    @State private var pendingScorerAttempt: PendingScorerAttempt?
    @State private var pendingKickAttempt: PendingKickAttempt?
    @State private var pendingSetPieceAttempt: PendingSetPieceAttempt?
    @State private var isSecondHalf = false
    // 起点プレーの持ち場は3つ:
    // selectedOriginRaw = 「次に始まる攻撃」への予約(チップの点灯)
    // team1/team2OriginRaw = いま走っているHOME/AWAYポゼッションに付いた起点
    // ポゼッション開始時に予約を引き取り、閉じるときに保存して消す。
    @State private var selectedOriginRaw: String?
    @State private var team1OriginRaw: String?
    @State private var team2OriginRaw: String?
    // 「開始直後の後付けタグ」かどうかを判定するための、各ポゼッションの開始時刻
    @State private var team1StartedAt: Date?
    @State private var team2StartedAt: Date?
    @State private var isShowingFinishConfirmation = false
    @State private var isShowingHalfChangeConfirmation = false
    @State private var isSubstitutionSheetPresented = false

    private let homeAccent = Color.blue
    private let awayAccent = Color.red
    private let cardBackground = Color(red: 0.04, green: 0.12, blue: 0.18)

    private var selectedTeamPlayers: [Player] {
        allPlayers
            .filter { $0.teamID == selectedInputTeam }
            .sorted { ($0.number ?? Int.max) < ($1.number ?? Int.max) }
    }

    private var scoreEvents: [StatEvent] {
        matchEvents.filter { ScoringCategory(rawValue: $0.category) != nil }
    }

    private var setPieceEvents: [StatEvent] {
        matchEvents.filter { $0.category == "lineout" || $0.category == "scrum" }
    }

    private var selectedInputTeam: UUID {
        selectedInputTeamID ?? match.homeTeamID
    }

    private var currentHalf: Int {
        isSecondHalf ? 1 : 0
    }

    private var undoableLastEvent: StatEvent? {
        matchEvents
            .filter { $0.category != "possession" }
            .sorted { ($0.half, $0.seconds) > ($1.half, $1.seconds) }
            .first
    }

    // チップに点灯させる値: 予約が最優先、なければ走行中の攻撃に付いている起点
    private var displayedOriginRaw: String? {
        if let selectedOriginRaw { return selectedOriginRaw }
        if team1State.isRunning, let team1OriginRaw { return team1OriginRaw }
        if team2State.isRunning, let team2OriginRaw { return team2OriginRaw }
        return nil
    }

    // チップをタップしたときの割り振り。実際の操作順は2通りあるので両対応:
    // ・攻撃が始まった直後(12秒以内)でまだ起点が無い → その攻撃への後付けタグ
    //   (「AWAY開始→TO」のように、始まってから付ける操作)
    // ・それ以外 → 「次に始まる攻撃」への予約
    //   (「SC→HOME開始」のように、始まる前に付ける操作。前の攻撃が
    //    まだ走っていても、その攻撃には付けない)
    private func applyOriginSelection(_ raw: String?) {
        guard let raw else {
            // 点灯中のチップをもう一度タップ = 解除(予約→走行中の順に消す)
            if selectedOriginRaw != nil {
                selectedOriginRaw = nil
            } else if team1State.isRunning, team1OriginRaw != nil {
                team1OriginRaw = nil
            } else if team2State.isRunning, team2OriginRaw != nil {
                team2OriginRaw = nil
            }
            return
        }

        let now = Date()
        if team1State.isRunning, team1OriginRaw == nil,
           let startedAt = team1StartedAt, now.timeIntervalSince(startedAt) < 12 {
            team1OriginRaw = raw
        } else if team2State.isRunning, team2OriginRaw == nil,
                  let startedAt = team2StartedAt, now.timeIntervalSince(startedAt) < 12 {
            team2OriginRaw = raw
        } else {
            selectedOriginRaw = raw
        }
    }

    // トライに付ける起点: 走っている攻撃の起点を最優先、なければ予約中のチップ
    private func attackOrigin(for teamID: UUID) -> String? {
        if teamID == match.homeTeamID, team1State.isRunning, let team1OriginRaw { return team1OriginRaw }
        if teamID == match.awayTeamID, team2State.isRunning, let team2OriginRaw { return team2OriginRaw }
        return selectedOriginRaw
    }

    private var inputTeamSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36)
            .onEnded { value in
                switchInputTeamIfNeeded(width: value.translation.width, height: value.translation.height)
            }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.03, blue: 0.08),
                    Color(red: 0.04, green: 0.09, blue: 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                topBar
                matchHeaderCard
                clockCard
                possessionDashboard
                originCard
                actionGrid

                // 余った縦スペースはここに集約。上に空白が溜まらないよう
                // コンテンツを上詰めにし、下段ボタンは画面の下に置く。
                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    undoButton
                    penaltyButton
                    substitutionButton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .simultaneousGesture(inputTeamSwipeGesture)

            if pendingKickAttempt != nil {
                kickEntryPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if pendingScorerAttempt != nil {
                scorerEntryPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if pendingSetPieceAttempt != nil {
                setPieceResultPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "この試合を終了しますか？",
            isPresented: $isShowingFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button("終了する", role: .destructive) {
                finishMatch()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("終了するとサマリーで集計を見られるようになります。")
        }
        .confirmationDialog(
            "後半に切り替えますか？",
            isPresented: $isShowingHalfChangeConfirmation,
            titleVisibility: .visible
        ) {
            Button("はい") {
                switchToSecondHalf()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("Time は 0:00 に戻ります。前半の記録は保持されます。")
        }
        .onAppear {
            if selectedInputTeamID == nil {
                selectedInputTeamID = match.homeTeamID
            }
            // 記録中に画面が自動ロックすると計測が見えなくなるため、
            // この画面を開いている間だけスリープを止める
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // この試合に登場した選手の背番号を今の値で控えておく
            // (後からチームページで番号を変えても、この試合の表示が変わらないように)
            MatchNumbering.freezeNumbers(forMatch: match.id, context: modelContext)
        }
        .sheet(item: $scoringEventForPlayerSelection) { event in
            PlayerSelectionSheet(
                players: players(for: event),
                title: playerSelectionTitle(for: event),
                numberFor: { player in
                    MatchNumbering.number(for: player, matchID: match.id, lineups: matchLineupEntries)
                }
            ) { player in
                event.playerID = player?.id
                try? modelContext.save()
                scoringEventForPlayerSelection = nil
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isSubstitutionSheetPresented) {
            SubstitutionAddSheet(
                match: match,
                teams: teams,
                players: allPlayers,
                lineups: matchLineupEntries,
                initialHalf: currentHalf,
                initialMinute: timeState.elapsedSeconds(at: Date()) / 60,
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
                    MatchNumbering.freezeNumbers(forMatch: match.id, context: modelContext)
                }
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - Main layout

    private var topBar: some View {
        ZStack {
            Text("試合記録")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.bold))
                        .frame(width: 42, height: 42)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Spacer()

                Button("試合終了") {
                    isShowingFinishConfirmation = true
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.red)
                .frame(width: 96, height: 42)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red, lineWidth: 1.5)
                )
            }
        }
    }

    // スコア + 両チームのロゴ(=記録対象の切替ボタン)。時計は別カードに分ける。
    // 得点は ZStack の中央に置き、ロゴは左右の端に載せることで、
    // ロゴの幅に関係なく得点が画面中央(縦軸)に来るようにする。
    private var matchHeaderCard: some View {
        VStack(spacing: 6) {
            ZStack {
                HStack(spacing: 4) {
                    teamIdentity(teamID: match.homeTeamID, label: "HOME", accent: homeAccent, alignment: .leading)
                    Spacer(minLength: 0)
                    teamIdentity(teamID: match.awayTeamID, label: "AWAY", accent: awayAccent, alignment: .trailing)
                }

                VStack(spacing: 4) {
                    Text("\(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID))")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    HStack(spacing: 12) {
                        halfScoreLabel("1ST", half: 0)
                        halfScoreLabel("2ND", half: 1)
                    }
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.78))
                }
            }

            Text("ロゴをタップで記録対象を切替")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .recordingCardBackground()
    }

    // 試合時間の枠。時間を ZStack の中央に固定し、前半/後半トグルと開始/停止は
    // 左右の端に載せる。ボタンの幅が違っても時間が画面中央(縦軸)からずれない。
    // 左右のボタンを同じ幅の枠に入れることで、中央の時間が
    // 画面中央からずれず、大きくしてもボタンに重ならないようにする。
    private var clockCard: some View {
        HStack(spacing: 8) {
            Button(isSecondHalf ? "後半" : "前半") {
                if !isSecondHalf {
                    isShowingHalfChangeConfirmation = true
                }
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(homeAccent)
            .frame(width: 72, height: 50)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .disabled(isSecondHalf)
            .frame(width: 104, alignment: .leading)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timeState.elapsedText(at: context.date))
                    .font(.system(size: 38, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity)
            }

            Button {
                toggleTime()
            } label: {
                Label(
                    timeState.isRunning ? "停止" : "開始",
                    systemImage: timeState.isRunning ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 104, height: 50)
                .background(
                    LinearGradient(
                        colors: [homeAccent, homeAccent.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .frame(width: 104, alignment: .trailing)
        }
        .padding(10)
        .recordingCardBackground()
    }

    // チームロゴが「記録対象」の切替ボタンを兼ねる。
    // 選択中: ロゴにチームカラーの枠+ラベル塗りつぶし。非選択: 全体を薄く。
    private func teamIdentity(teamID: UUID, label: String, accent: Color, alignment: HorizontalAlignment) -> some View {
        let isSelected = selectedInputTeam == teamID

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedInputTeamID = teamID
            }
        } label: {
            VStack(alignment: alignment, spacing: 3) {
                teamLogoBox(for: teamID)
                    .frame(width: 82, height: 82)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(accent, lineWidth: isSelected ? 3 : 0)
                    )

                Text(teamName(for: teamID))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                    .frame(width: 96, alignment: alignment == .leading ? .leading : .trailing)

                Text(label)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(isSelected ? .white : accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(isSelected ? accent : accent.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .opacity(isSelected ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 90, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var possessionDashboard: some View {
        VStack(spacing: 6) {
            Label("BIP / ポゼッション", systemImage: "clock")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                possessionTile(
                    label: "HOME",
                    teamName: teamName(for: match.homeTeamID),
                    accent: homeAccent,
                    state: team1State,
                    action: toggleTeam1
                )

                possessionTile(
                    label: "BIP",
                    teamName: "BIP",
                    accent: .orange,
                    state: bipState,
                    action: toggleBIP
                )

                possessionTile(
                    label: "AWAY",
                    teamName: teamName(for: match.awayTeamID),
                    accent: awayAccent,
                    state: team2State,
                    action: toggleTeam2
                )
            }

        }
        .padding(8)
        .recordingCardBackground()
    }

    // いま進行中の攻撃が何から始まったか(任意)。旧「記録対象」の位置に置く。
    // 選んだ値はポゼッション保存時とトライに付き、保存されるとリセットされる。
    private var originCard: some View {
        originChipRow(selectedRaw: displayedOriginRaw) { newValue in
            applyOriginSelection(newValue)
        }
        .padding(8)
        .recordingCardBackground()
    }

    // 起点ボタンの列。スクロールさせず全ボタンを等幅で並べる
    // (横スクロールにすると HOME/AWAY 切替スワイプと衝突するため)。
    private func originChipRow(selectedRaw: String?, onSelect: @escaping (String?) -> Void) -> some View {
        HStack(spacing: 6) {
            Text("起点")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .frame(minHeight: 50)
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.85), Color.blue.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

            ForEach(PlayOrigin.allCases) { origin in
                let isSelected = selectedRaw == origin.rawValue
                Button {
                    onSelect(isSelected ? nil : origin.rawValue)
                } label: {
                    Text(origin.shortName)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.66))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(isSelected ? Color.teal.opacity(0.85) : Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.teal : Color.white.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // タイル全体が開始/停止ボタン。中の小さいボタンだと押しづらいため、
    // 枠のどこを押しても反応する。計測中はチームカラーで塗って一目でわかるようにする。
    private func possessionTile(
        label: String,
        teamName: String,
        accent: Color,
        state: V3TimerState,
        action: @escaping () -> Void
    ) -> some View {
        let isRunning = state.isRunning
        let isDisabled = label == "BIP" && !timeState.isRunning

        return Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(minWidth: 42)
                        .background(accent.opacity(isRunning ? 1.0 : 0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(teamName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(state.elapsedText(at: context.date))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.55)
                }

                Text(isRunning ? "計測中・タップで停止" : "タップで開始")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isRunning ? accent : .white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(isRunning ? accent.opacity(0.16) : Color.black.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isRunning ? accent : Color.white.opacity(0.08), lineWidth: isRunning ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            scoringCard(.tryScore, accent: .green, symbol: "rugbyball")
            scoringCard(.conversion, accent: .purple, symbol: "figure.rugby")
            scoringCard(.penaltyGoal, accent: .blue, symbol: "p.circle")
            scoringCard(.dropGoal, accent: .yellow, symbol: "d.circle")
            setPieceRow(title: "ラインアウト", category: "lineout", symbol: "figure.strengthtraining.traditional", accent: .teal)
            setPieceRow(title: "スクラム", category: "scrum", symbol: "person.3.fill", accent: .indigo)
        }
        .padding(8)
        .recordingCardBackground()
    }

    private func scoringCard(_ category: ScoringCategory, accent: Color, symbol: String) -> some View {
        Button {
            recordScore(category)
        } label: {
            actionRowLabel(
                title: category.displayName,
                symbol: symbol,
                countText: "\(countEvents(category: category.rawValue))",
                accent: accent
            )
        }
        .buttonStyle(.plain)
    }

    // 1行型のアクションボタン共通レイアウト:
    // [丸アイコン] 名前 …… 回数 >
    private func actionRowLabel(title: String, symbol: String, countText: String, accent: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.18))
                .clipShape(Circle())

            Text(title)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.45)

            Spacer(minLength: 2)

            Text(countText)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.92), accent.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func setPieceRow(title: String, category: String, symbol: String, accent: Color) -> some View {
        let events = setPieceEvents.filter { $0.category == category && $0.teamID == selectedInputTeam }
        let successCount = events.filter { $0.outcome == "success" }.count
        let totalCount = events.count

        return Button {
            pendingScorerAttempt = nil
            pendingKickAttempt = nil
            pendingSetPieceAttempt = PendingSetPieceAttempt(
                title: title,
                category: category,
                symbol: symbol,
                teamID: selectedInputTeam,
                seconds: timeState.elapsedSeconds(at: Date()),
                half: currentHalf
            )
        } label: {
            actionRowLabel(
                title: title,
                symbol: symbol,
                countText: "\(successCount)/\(totalCount)",
                accent: accent
            )
        }
        .buttonStyle(.plain)
    }

    private var undoButton: some View {
        Button {
            undoLastEvent()
        } label: {
            Label("取り消し", systemImage: "trash.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.72, green: 0.14, blue: 0.18), Color(red: 0.45, green: 0.08, blue: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(undoableLastEvent == nil)
        .opacity(undoableLastEvent == nil ? 0.45 : 1)
    }

    // 反則を「記録対象のチームが犯した」として1件記録するボタン
    private var penaltyButton: some View {
        Button {
            recordPenalty()
        } label: {
            Label("反則 \(penaltyCount)", systemImage: "flag.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.85, green: 0.48, blue: 0.10), Color(red: 0.58, green: 0.30, blue: 0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // 交代を今の試合時間で記録するボタン
    private var substitutionButton: some View {
        Button {
            isSubstitutionSheetPresented = true
        } label: {
            Label("交代", systemImage: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.cyan)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.20, blue: 0.36), Color(red: 0.05, green: 0.12, blue: 0.24)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var setPieceResultPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 74, height: 5)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Image(systemName: pendingSetPieceAttempt?.symbol ?? "sportscourt")
                    .font(.title3.weight(.bold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pendingSetPieceAttempt?.title ?? "セットプレー")
                        .font(.title3.weight(.bold))
                    Text("結果を記録")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
            }
            .foregroundStyle(.white)

            resultButtons(
                successAction: { recordPendingSetPiece(outcome: "success") },
                failureAction: { recordPendingSetPiece(outcome: "fail") }
            )
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 16)
    }

    private var scorerEntryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 74, height: 5)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Image(systemName: "figure.rugby")
                    .font(.title3.weight(.bold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pendingScorerAttempt?.category.displayName ?? "トライ")
                        .font(.title3.weight(.bold))
                    Text("得点者を選択してください")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
            }
            .foregroundStyle(.white)

            if let attempt = pendingScorerAttempt {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(players(forTeamID: attempt.teamID)) { player in
                            scorerPlayerButton(player)
                        }
                        noPlayerScorerButton
                    }
                    .padding(.vertical, 2)
                }

                // 攻撃の起点(任意)。チップで選んでいた値が引き継がれ、ここで直せる
                originChipRow(selectedRaw: attempt.originRaw) { newValue in
                    pendingScorerAttempt?.originRaw = newValue
                }
            }

            confirmScorerButton(isEnabled: pendingScorerAttempt?.hasSelectedPlayer == true)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 16)
    }

    private var kickEntryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 74, height: 5)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.title3.weight(.bold))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pendingKickAttempt?.category.displayName ?? "キック")
                        .font(.title3.weight(.bold))
                    Text("キッカーを選択してください")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
            }
            .foregroundStyle(.white)

            if let attempt = pendingKickAttempt {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(players(forTeamID: attempt.teamID)) { player in
                            kickPlayerButton(player)
                        }
                        noPlayerKickButton
                    }
                    .padding(.vertical, 2)
                }
            }

            resultButtons(
                isEnabled: pendingKickAttempt?.hasSelectedPlayer == true,
                successAction: { recordPendingKick(outcome: "success") },
                failureAction: { recordPendingKick(outcome: "fail") }
            )
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 16)
    }

    private func resultButtons(
        isEnabled: Bool = true,
        successAction: @escaping () -> Void,
        failureAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Button {
                successAction()
            } label: {
                Text("成功")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)

            Button {
                failureAction()
            } label: {
                Text("失敗")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
        }
    }

    private func confirmScorerButton(isEnabled: Bool) -> some View {
        Button {
            recordPendingScorer()
        } label: {
            Text("確定")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 66)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func scorerPlayerButton(_ player: Player) -> some View {
        let isSelected = pendingScorerAttempt?.playerID == player.id && pendingScorerAttempt?.hasSelectedPlayer == true

        return Button {
            pendingScorerAttempt?.playerID = player.id
            pendingScorerAttempt?.hasSelectedPlayer = true
        } label: {
            VStack(spacing: 6) {
                playerAvatar(player: player, isSelected: isSelected)
                Text(MatchNumbering.numberLabel(for: player, matchID: match.id, lineups: matchLineupEntries))
                    .font(.caption.weight(.bold).monospacedDigit())
                Text(player.name ?? "名前未設定")
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 74)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var noPlayerScorerButton: some View {
        let isSelected = pendingScorerAttempt?.playerID == nil && pendingScorerAttempt?.hasSelectedPlayer == true

        return Button {
            pendingScorerAttempt?.playerID = nil
            pendingScorerAttempt?.hasSelectedPlayer = true
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.95 : 0.28), lineWidth: isSelected ? 3 : 1)
                        .frame(width: 68, height: 68)
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 68, height: 68)
                }
                Text("その他")
                    .font(.caption.weight(.bold))
                Text("選手なし")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func kickPlayerButton(_ player: Player) -> some View {
        let isSelected = pendingKickAttempt?.playerID == player.id && pendingKickAttempt?.hasSelectedPlayer == true

        return Button {
            pendingKickAttempt?.playerID = player.id
            pendingKickAttempt?.hasSelectedPlayer = true
        } label: {
            VStack(spacing: 6) {
                playerAvatar(player: player, isSelected: isSelected)
                Text(MatchNumbering.numberLabel(for: player, matchID: match.id, lineups: matchLineupEntries))
                    .font(.caption.weight(.bold).monospacedDigit())
                Text(player.name ?? "名前未設定")
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 74)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var noPlayerKickButton: some View {
        let isSelected = pendingKickAttempt?.playerID == nil && pendingKickAttempt?.hasSelectedPlayer == true

        return Button {
            pendingKickAttempt?.playerID = nil
            pendingKickAttempt?.hasSelectedPlayer = true
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.95 : 0.28), lineWidth: isSelected ? 3 : 1)
                        .frame(width: 68, height: 68)
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 68, height: 68)
                }
                Text("その他")
                    .font(.caption.weight(.bold))
                Text("選手なし")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func playerAvatar(player: Player, isSelected: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            if let imagePath = player.imagePath, let uiImage = ImageStorage.image(named: imagePath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 68, height: 68)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 68, height: 68)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.7))
                    )
            }

            Circle()
                .stroke(isSelected ? homeAccent : Color.white.opacity(0.3), lineWidth: isSelected ? 4 : 1)
                .frame(width: 68, height: 68)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(homeAccent)
                    .background(Circle().fill(.white))
                    .offset(x: 4, y: -4)
            }
        }
    }

    // MARK: - Input target switching

    private func switchInputTeamIfNeeded(width: CGFloat, height: CGFloat) {
        guard abs(width) > 64, abs(width) > abs(height) * 1.4 else { return }

        withAnimation(.easeInOut(duration: 0.16)) {
            selectedInputTeamID = width < 0 ? match.awayTeamID : match.homeTeamID
        }
    }

    // MARK: - Half change

    private func switchToSecondHalf() {
        let now = Date()
        stopBIPAndTeams(at: now)
        if timeState.isRunning {
            _ = timeState.stop(at: now)
        }
        timeState.reset()
        isSecondHalf = true
    }

    // MARK: - Finish match

    private func finishMatch() {
        if timeState.isRunning {
            toggleTime()
        }

        let marker = StatEvent(
            matchID: match.id,
            teamID: nil,
            category: "match_state",
            outcome: "finished",
            seconds: timeState.elapsedSeconds(at: Date()),
            half: currentHalf
        )
        modelContext.insert(marker)
        try? modelContext.save()

        dismiss()
    }

    // MARK: - Timer toggling

    private func toggleTime() {
        let now = Date()
        if timeState.isRunning {
            stopBIPAndTeams(at: now)
            _ = timeState.stop(at: now)
        } else {
            timeState.start(at: now)
        }
    }

    private func toggleBIP() {
        guard timeState.isRunning else { return }
        let now = Date()
        if bipState.isRunning {
            stopBIPAndTeams(at: now)
        } else {
            bipState.start(at: now)
        }
    }

    private func toggleTeam1() {
        let now = Date()
        ensureTimeAndBIPRunning(at: now)
        if team1State.isRunning {
            stopTeam1(at: now)
        } else {
            stopTeam2(at: now)
            team1State.start(at: now)
            // チップで予約されていた起点を、この攻撃が引き取る
            team1OriginRaw = selectedOriginRaw
            selectedOriginRaw = nil
            team1StartedAt = now
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedInputTeamID = match.homeTeamID
            }
        }
    }

    private func toggleTeam2() {
        let now = Date()
        ensureTimeAndBIPRunning(at: now)
        if team2State.isRunning {
            stopTeam2(at: now)
        } else {
            stopTeam1(at: now)
            team2State.start(at: now)
            // チップで予約されていた起点を、この攻撃が引き取る
            team2OriginRaw = selectedOriginRaw
            selectedOriginRaw = nil
            team2StartedAt = now
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedInputTeamID = match.awayTeamID
            }
        }
    }

    private func ensureTimeAndBIPRunning(at date: Date) {
        timeState.start(at: date)
        bipState.start(at: date)
    }

    private func stopBIPAndTeams(at date: Date) {
        stopTeam1(at: date)
        stopTeam2(at: date)
        if let seconds = bipState.stop(at: date) {
            savePossessionEvent(
                teamID: nil,
                outcome: "none",
                seconds: seconds,
                startSeconds: max(0, timeState.elapsedSeconds(at: date) - seconds)
            )
        }
    }

    private func stopTeam1(at date: Date) {
        if let seconds = team1State.stop(at: date) {
            savePossessionEvent(
                teamID: match.homeTeamID,
                outcome: "own",
                seconds: seconds,
                startSeconds: max(0, timeState.elapsedSeconds(at: date) - seconds),
                origin: team1OriginRaw
            )
            team1OriginRaw = nil
            team1StartedAt = nil
        }
    }

    private func stopTeam2(at date: Date) {
        if let seconds = team2State.stop(at: date) {
            savePossessionEvent(
                teamID: match.awayTeamID,
                outcome: "own",
                seconds: seconds,
                startSeconds: max(0, timeState.elapsedSeconds(at: date) - seconds),
                origin: team2OriginRaw
            )
            team2OriginRaw = nil
            team2StartedAt = nil
        }
    }

    // MARK: - Event saving

    private func players(for event: StatEvent) -> [Player] {
        guard let teamID = event.teamID else { return selectedTeamPlayers }
        return players(forTeamID: teamID)
    }

    private func players(forTeamID teamID: UUID) -> [Player] {
        // スタメン登録の並び順を尊重しつつ、登録外の選手は番号順で末尾に。
        // 絞り込みは行わない（登録外も選択肢として残す）。
        let teamLineup = matchLineupEntries.filter { $0.teamID == teamID }
        let orderByPlayer = Dictionary(
            teamLineup.map { ($0.playerID, $0.order) },
            uniquingKeysWith: { first, _ in first }
        )
        let roleByPlayer = Dictionary(
            teamLineup.map { ($0.playerID, $0.role) },
            uniquingKeysWith: { first, _ in first }
        )
        return allPlayers
            .filter { $0.teamID == teamID }
            .sorted { lhs, rhs in
                let lRank = lineupRoleRank(roleByPlayer[lhs.id])
                let rRank = lineupRoleRank(roleByPlayer[rhs.id])
                if lRank != rRank { return lRank < rRank }
                if let lOrder = orderByPlayer[lhs.id], let rOrder = orderByPlayer[rhs.id] {
                    return lOrder < rOrder
                }
                return (lhs.number ?? Int.max) < (rhs.number ?? Int.max)
            }
    }

    private func lineupRoleRank(_ role: String?) -> Int {
        switch role {
        case "starter": return 0
        case "reserve": return 1
        default: return 2
        }
    }

    private func playerSelectionTitle(for event: StatEvent) -> String {
        guard let category = ScoringCategory(rawValue: event.category) else {
            return "得点者を選択"
        }
        return playerSelectionTitle(for: category)
    }

    private func playerSelectionTitle(for category: ScoringCategory) -> String {
        category.requiresResultSelection ? "キッカーを選択" : "得点者を選択"
    }

    private func recordScore(_ category: ScoringCategory) {
        pendingScorerAttempt = nil
        pendingKickAttempt = nil
        pendingSetPieceAttempt = nil

        if category.requiresResultSelection {
            pendingKickAttempt = PendingKickAttempt(
                category: category,
                teamID: selectedInputTeam,
                seconds: timeState.elapsedSeconds(at: Date()),
                half: currentHalf
            )
            return
        }

        pendingScorerAttempt = PendingScorerAttempt(
            category: category,
            teamID: selectedInputTeam,
            seconds: timeState.elapsedSeconds(at: Date()),
            half: currentHalf,
            originRaw: attackOrigin(for: selectedInputTeam)
        )
    }

    private func recordPendingScorer() {
        guard let attempt = pendingScorerAttempt, attempt.hasSelectedPlayer else { return }
        pendingScorerAttempt = nil
        saveScoreEvent(
            category: attempt.category,
            outcome: "success",
            teamID: attempt.teamID,
            playerID: attempt.playerID,
            seconds: attempt.seconds,
            half: attempt.half,
            origin: attempt.originRaw,
            opensPlayerSheet: false
        )
        // 予約中のチップをこのトライに使った場合だけ消費する。
        // 走行中の攻撃に付いている分は、ポゼッションが閉じるときに消える。
        if attempt.originRaw != nil, attempt.originRaw == selectedOriginRaw {
            selectedOriginRaw = nil
        }
    }

    private func recordPendingKick(outcome: String) {
        guard let attempt = pendingKickAttempt, attempt.hasSelectedPlayer else { return }
        pendingKickAttempt = nil
        saveScoreEvent(
            category: attempt.category,
            outcome: outcome,
            teamID: attempt.teamID,
            playerID: attempt.playerID,
            seconds: attempt.seconds,
            half: attempt.half,
            opensPlayerSheet: false
        )
    }

    private func recordPendingSetPiece(outcome: String) {
        guard let attempt = pendingSetPieceAttempt else { return }
        pendingSetPieceAttempt = nil
        saveSetPieceEvent(
            category: attempt.category,
            outcome: outcome,
            teamID: attempt.teamID,
            seconds: attempt.seconds,
            half: attempt.half
        )
    }

    private func saveScoreEvent(
        category: ScoringCategory,
        outcome: String,
        teamID: UUID? = nil,
        playerID: UUID? = nil,
        seconds: Int? = nil,
        half: Int? = nil,
        origin: String? = nil,
        opensPlayerSheet: Bool
    ) {
        let event = StatEvent(
            matchID: match.id,
            teamID: teamID ?? selectedInputTeam,
            playerID: playerID,
            category: category.rawValue,
            outcome: outcome,
            seconds: seconds ?? timeState.elapsedSeconds(at: Date()),
            half: half ?? currentHalf,
            origin: origin
        )
        modelContext.insert(event)
        try? modelContext.save()

        if opensPlayerSheet {
            scoringEventForPlayerSelection = event
        }
    }

    private func countEvents(category: String) -> Int {
        scoreEvents.filter { $0.category == category && $0.teamID == selectedInputTeam }.count
    }

    private func saveSetPieceEvent(
        category: String,
        outcome: String,
        teamID: UUID,
        seconds: Int,
        half: Int
    ) {
        let event = StatEvent(
            matchID: match.id,
            teamID: teamID,
            category: category,
            outcome: outcome,
            seconds: seconds,
            half: half
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func savePossessionEvent(teamID: UUID?, outcome: String, seconds: Int, startSeconds: Int? = nil, origin: String? = nil) {
        guard seconds > 0 else { return }

        let event = StatEvent(
            matchID: match.id,
            teamID: teamID,
            category: "possession",
            outcome: outcome,
            seconds: seconds,
            startSeconds: startSeconds,
            half: currentHalf,
            origin: origin
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    // ペナルティ(反則)を「犯したチーム」に1件記録する
    private func recordPenalty() {
        let event = StatEvent(
            matchID: match.id,
            teamID: selectedInputTeam,
            category: "penalty",
            outcome: "conceded",
            seconds: timeState.elapsedSeconds(at: Date()),
            half: currentHalf
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    private var penaltyCount: Int {
        matchEvents.filter { $0.category == "penalty" && $0.teamID == selectedInputTeam }.count
    }

    private func undoLastEvent() {
        guard let target = undoableLastEvent else { return }
        modelContext.delete(target)
        try? modelContext.save()
    }

    // MARK: - Score totals

    private func score(for teamID: UUID, half: Int? = nil) -> Int {
        scoreEvents
            .filter { event in
                event.teamID == teamID && (half == nil || event.half == half)
            }
            .reduce(0) { partial, event in
                partial + scoreValue(for: event)
            }
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

    private func halfScoreLabel(_ label: String, half: Int) -> some View {
        Text("\(label) \(score(for: match.homeTeamID, half: half))-\(score(for: match.awayTeamID, half: half))")
    }

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
    }

    @ViewBuilder
    private func teamLogoBox(for teamID: UUID) -> some View {
        let team = teams.first { $0.id == teamID }
        Group {
            if let team, let logoName = team.logoPath, let uiImage = ImageStorage.image(named: logoName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(12)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PendingScorerAttempt {
    let category: ScoringCategory
    let teamID: UUID
    let seconds: Int
    let half: Int
    var playerID: UUID?
    var hasSelectedPlayer = false
    // 攻撃の起点(チップで選択済みの値を引き継ぎ、パネル上でも変更できる)
    var originRaw: String?
}

private struct PendingKickAttempt {
    let category: ScoringCategory
    let teamID: UUID
    let seconds: Int
    let half: Int
    var playerID: UUID?
    var hasSelectedPlayer = false
}

private struct PendingSetPieceAttempt {
    let title: String
    let category: String
    let symbol: String
    let teamID: UUID
    let seconds: Int
    let half: Int
}

private struct V3TimerState {
    // 表示は分:秒だが、内部では秒以下のずれを失わないよう TimeInterval (Double) で持つ。
    // これで 1 秒未満の停止/開始を繰り返しても累積していく（00:00 のまま固まらない）。
    private var accumulatedSeconds: TimeInterval = 0
    private var startedAt: Date?

    var isRunning: Bool {
        startedAt != nil
    }

    mutating func toggle(at date: Date) {
        if isRunning {
            _ = stop(at: date)
        } else {
            start(at: date)
        }
    }

    mutating func start(at date: Date) {
        guard !isRunning else { return }
        startedAt = date
    }

    mutating func stop(at date: Date) -> Int? {
        guard let startedAt else { return nil }
        let interval = max(0, date.timeIntervalSince(startedAt))
        accumulatedSeconds += interval
        self.startedAt = nil
        return Int(interval)
    }

    mutating func reset() {
        accumulatedSeconds = 0
        startedAt = nil
    }

    func elapsedText(at date: Date) -> String {
        let seconds = elapsedSeconds(at: date)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func elapsedSeconds(at date: Date) -> Int {
        Int(elapsedInterval(at: date))
    }

    func elapsedInterval(at date: Date) -> TimeInterval {
        guard let startedAt else {
            return accumulatedSeconds
        }
        return accumulatedSeconds + max(0, date.timeIntervalSince(startedAt))
    }
}

private extension View {
    func recordingCardBackground() -> some View {
        self
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.13, blue: 0.24),
                        Color(red: 0.03, green: 0.07, blue: 0.14)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

#Preview {
    NavigationStack {
        V3RecordingView(
            match: Match(
                tournamentID: UUID(),
                homeTeamID: UUID(),
                awayTeamID: UUID(),
                playedAt: Date()
            )
        )
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
