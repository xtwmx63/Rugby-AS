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
    @State private var isShowingFinishConfirmation = false
    @State private var isShowingHalfChangeConfirmation = false

    private let homeAccent = Color.blue
    private let awayAccent = Color.red
    private let fieldBackground = Color(red: 0.02, green: 0.06, blue: 0.10)
    private let cardBackground = Color(red: 0.04, green: 0.12, blue: 0.18)
    // 「コンバージョン」など長い文字でも縮まないよう、6 種のラベルと回数表示は
    // 固定サイズで揃える。1 行に収まる範囲で十分大きいサイズを選定。
    private let actionLabelFont: Font = .system(size: 14, weight: .bold)
    private let actionCountFont: Font = .system(size: 22, weight: .bold).monospacedDigit()

    private var selectedTeamPlayers: [Player] {
        allPlayers
            .filter { $0.teamID == selectedInputTeam }
            .sorted { $0.number < $1.number }
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

    private var bottomPanelIsPresented: Bool {
        pendingScorerAttempt != nil || pendingKickAttempt != nil || pendingSetPieceAttempt != nil
    }

    private var inputTeamSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36)
            .onEnded { value in
                switchInputTeamIfNeeded(width: value.translation.width, height: value.translation.height)
            }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            fieldBackground.ignoresSafeArea()

            VStack(spacing: 6) {
                topBar
                scoreCard
                clockCard
                possessionDashboard
                inputTargetCard
                actionGrid
                undoButton
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 8)
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
        }
        .sheet(item: $scoringEventForPlayerSelection) { event in
            PlayerSelectionSheet(players: players(for: event), title: playerSelectionTitle(for: event)) { player in
                event.playerID = player?.id
                try? modelContext.save()
                scoringEventForPlayerSelection = nil
            }
            .presentationDetents([.medium, .large])
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

    private var clockCard: some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timeState.elapsedText(at: context.date))
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: 112)
            }

            HStack {
                Button(isSecondHalf ? "後半" : "前半") {
                    if !isSecondHalf {
                        isShowingHalfChangeConfirmation = true
                    }
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(homeAccent)
                .frame(width: 58, height: 36)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .disabled(isSecondHalf)

                Spacer()

                Button(timeState.isRunning ? "停止" : "開始") {
                    toggleTime()
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 86, height: 44)
                .background(homeAccent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(8)
        .recordingCardBackground()
    }

    private var scoreCard: some View {
        ZStack {
            VStack(spacing: 4) {
                Text("\(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 10) {
                    halfScoreLabel("1ST", half: 0)
                    halfScoreLabel("2ND", half: 1)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
            }
            .frame(width: 168)

            HStack(spacing: 10) {
                teamIdentity(teamID: match.homeTeamID, label: "HOME", accent: homeAccent, alignment: .leading)

                Spacer()

                teamIdentity(teamID: match.awayTeamID, label: "AWAY", accent: awayAccent, alignment: .trailing)
            }
        }
        .padding(8)
        .recordingCardBackground()
    }

    private func teamIdentity(teamID: UUID, label: String, accent: Color, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            teamLogoBox(for: teamID)
                .frame(width: 48, height: 48)

            Text(teamName(for: teamID))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .frame(width: 80, alignment: alignment == .leading ? .leading : .trailing)

            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(accent.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: 78, alignment: alignment == .leading ? .leading : .trailing)
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
                    buttonTitle: team1State.isRunning ? "停止中" : "開始",
                    action: toggleTeam1
                )

                possessionTile(
                    label: "BIP",
                    teamName: "BIP",
                    accent: .orange,
                    state: bipState,
                    buttonTitle: bipState.isRunning ? "一時停止中" : "開始",
                    action: toggleBIP
                )

                possessionTile(
                    label: "AWAY",
                    teamName: teamName(for: match.awayTeamID),
                    accent: awayAccent,
                    state: team2State,
                    buttonTitle: team2State.isRunning ? "停止中" : "開始",
                    action: toggleTeam2
                )
            }
        }
        .padding(8)
        .recordingCardBackground()
    }

    private func possessionTile(
        label: String,
        teamName: String,
        accent: Color,
        state: V3TimerState,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .frame(minWidth: 42)
                    .background(accent.opacity(0.7))
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
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.55)
            }

            Button {
                action()
            } label: {
                Text(buttonTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.plain)
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .disabled(label == "BIP" && !timeState.isRunning)
            .opacity(label == "BIP" && !timeState.isRunning ? 0.45 : 1)
        }
        .padding(6)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var inputTargetCard: some View {
        HStack(spacing: 10) {
            Label("記録対象", systemImage: "person.3")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 96, alignment: .leading)

            targetButton(title: "HOME", teamID: match.homeTeamID, accent: homeAccent)
            targetButton(title: "AWAY", teamID: match.awayTeamID, accent: awayAccent)
        }
        .padding(8)
        .recordingCardBackground()
    }

    private func targetButton(title: String, teamID: UUID, accent: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedInputTeamID = teamID
            }
        } label: {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(selectedInputTeam == teamID ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(selectedInputTeam == teamID ? accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.title3.weight(.bold))
                        .frame(width: 26)
                    Text(category.displayName)
                        .font(actionLabelFont)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack {
                    Spacer()
                    Text("\(countEvents(category: category.rawValue))")
                        .font(actionCountFont)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(accent.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.title3.weight(.bold))
                        .frame(width: 26)

                    Text(title)
                        .font(actionLabelFont)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack {
                    Spacer()
                    Text("\(successCount)/\(totalCount)")
                        .font(actionCountFont)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 68)
            .background(accent.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.75), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var undoButton: some View {
        Button {
            undoLastEvent()
        } label: {
            Text("取り消し")
                .font(.headline.weight(.bold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color.red.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(undoableLastEvent == nil)
        .opacity(undoableLastEvent == nil ? 0.45 : 1)
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
                Text("#\(player.number)")
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
                Text("#\(player.number)")
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
                startSeconds: max(0, timeState.elapsedSeconds(at: date) - seconds)
            )
        }
    }

    private func stopTeam2(at date: Date) {
        if let seconds = team2State.stop(at: date) {
            savePossessionEvent(
                teamID: match.awayTeamID,
                outcome: "own",
                seconds: seconds,
                startSeconds: max(0, timeState.elapsedSeconds(at: date) - seconds)
            )
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
                return lhs.number < rhs.number
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
            half: currentHalf
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
            opensPlayerSheet: false
        )
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
        opensPlayerSheet: Bool
    ) {
        let event = StatEvent(
            matchID: match.id,
            teamID: teamID ?? selectedInputTeam,
            playerID: playerID,
            category: category.rawValue,
            outcome: outcome,
            seconds: seconds ?? timeState.elapsedSeconds(at: Date()),
            half: half ?? currentHalf
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

    private func savePossessionEvent(teamID: UUID?, outcome: String, seconds: Int, startSeconds: Int? = nil) {
        guard seconds > 0 else { return }

        let event = StatEvent(
            matchID: match.id,
            teamID: teamID,
            category: "possession",
            outcome: outcome,
            seconds: seconds,
            startSeconds: startSeconds,
            half: currentHalf
        )
        modelContext.insert(event)
        try? modelContext.save()
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PendingScorerAttempt {
    let category: ScoringCategory
    let teamID: UUID
    let seconds: Int
    let half: Int
    var playerID: UUID?
    var hasSelectedPlayer = false
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
            .background(Color(red: 0.04, green: 0.12, blue: 0.18).opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
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
