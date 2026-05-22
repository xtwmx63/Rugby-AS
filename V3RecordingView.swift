//
//  V3RecordingView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/18.
//

import SwiftData
import SwiftUI

struct V3RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var teams: [Team]
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query private var allEvents: [StatEvent]

    let match: Match

    @State private var timeState = V3TimerState()
    @State private var bipState = V3TimerState()
    @State private var team1State = V3TimerState()
    @State private var team2State = V3TimerState()
    @State private var selectedInputTeamID: UUID?
    @State private var scoringEventForPlayerSelection: StatEvent?
    @State private var pendingKickAttempt: PendingKickAttempt?
    @State private var isShowingKickPlayerSelection = false
    @State private var isSecondHalf = false
    @State private var isShowingFinishConfirmation = false
    @State private var isShowingHalfChangeConfirmation = false

    private var selectedTeamPlayers: [Player] {
        allPlayers
            .filter { $0.teamID == selectedInputTeam }
            .sorted { $0.number < $1.number }
    }

    private var matchEvents: [StatEvent] {
        allEvents.filter { $0.matchID == match.id }
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

    private var inputTeamSelection: Binding<UUID> {
        Binding(
            get: { selectedInputTeam },
            set: { selectedInputTeamID = $0 }
        )
    }

    // 取り消し対象は「直前に手動で記録した1件」= 得点・セットプレーのうち最新。
    // ポゼッションは V3 のタイマー連動で自動保存されるため、ここでは触れない。
    // 現在の半分（前半=0, 後半=1）。StatEvent.half に保存する値。
    private var currentHalf: Int {
        isSecondHalf ? 1 : 0
    }

    // 取り消し対象は (half, seconds) の組で最大、つまり「最新の手動記録」。
    // 後半でも前半の seconds が大きい場合に誤って前半側を取らないよう半分で先に比較する。
    private var undoableLastEvent: StatEvent? {
        matchEvents
            .filter { $0.category != "possession" }
            .sorted { ($0.half, $0.seconds) > ($1.half, $1.seconds) }
            .first
    }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                headerBand
                possessionBand
                inputTeamPicker
                scoringRow
                setPieceCompact
                Spacer(minLength: 0)
                undoBand
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if pendingKickAttempt?.hasSelectedPlayer == true {
                kickResultPanel
            }
        }
        .navigationTitle("V3 記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("試合終了") {
                    isShowingFinishConfirmation = true
                }
                .tint(.red)
            }
        }
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
        }
        .sheet(item: $scoringEventForPlayerSelection) { event in
            PlayerSelectionSheet(players: players(for: event), title: playerSelectionTitle(for: event)) { player in
                event.playerID = player?.id
                try? modelContext.save()
                scoringEventForPlayerSelection = nil
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isShowingKickPlayerSelection) {
            if let attempt = pendingKickAttempt {
                PlayerSelectionSheet(players: players(forTeamID: attempt.teamID), title: playerSelectionTitle(for: attempt.category)) { player in
                    pendingKickAttempt?.playerID = player?.id
                    pendingKickAttempt?.hasSelectedPlayer = true
                    isShowingKickPlayerSelection = false
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Half change

    private func switchToSecondHalf() {
        // 走行中の BIP/Team1/Team2 を既存の処理で停止し、最後の区間を保存して締める。
        // Time を停止して 0:00 にリセットし、後半表示へ。
        // BIP/Team1/Team2 の累積秒は意図的にリセットしない（試合通算のポゼッション計測のため）。
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
        // タイマー走行中なら既存の toggleTime() で停止し、最後の区間を保存して締める。
        // ステートマシンは変更せず、既存処理を利用するだけ。
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

    // MARK: - Header band (Time / Score / Half)

    private var headerBand: some View {
        HStack(spacing: 12) {
            Spacer()

            // 左: 前後半トグル（Time の左へ移動）
            Button(isSecondHalf ? "後半" : "前半") {
                if !isSecondHalf {
                    isShowingHalfChangeConfirmation = true
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSecondHalf)

            // 中央: ラベル "Time" の下に 00:00 を縦積み（BIP/チームと同じ並び方）
            VStack(spacing: 2) {
                Text("Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timeState.elapsedText(at: context.date))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                }
            }

            // 右: 開始/停止ボタン
            Button(timeState.isRunning ? "停止" : "開始") {
                toggleTime()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Possession band (Team1 / BIP / Team2)

    private var possessionBand: some View {
        HStack(alignment: .top, spacing: 8) {
            teamColumn(
                teamID: match.homeTeamID,
                state: team1State,
                buttonTitle: team1State.isRunning ? "停止" : "開始",
                action: toggleTeam1
            )

            bipColumn

            teamColumn(
                teamID: match.awayTeamID,
                state: team2State,
                buttonTitle: team2State.isRunning ? "停止" : "開始",
                action: toggleTeam2
            )
        }
    }

    private func teamColumn(
        teamID: UUID,
        state: V3TimerState,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            teamLogoBox(for: teamID)

            teamTimerPanel(
                title: teamName(for: teamID),
                state: state,
                buttonTitle: buttonTitle,
                action: action
            )
        }
    }

    private var bipColumn: some View {
        VStack(spacing: 8) {
            scoreDisplay
            bipTimerPanel
        }
    }

    // 上段の3ボックス（ロゴ/スコア/ロゴ）は同じ正方形サイズで揃える。
    // スコア表示は内容が小さいので中央寄せして余白を持たせる。
    private var scoreDisplay: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            Text("\(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID))")
                .font(.system(size: 26, weight: .bold, design: .monospaced))

            VStack(spacing: 2) {
                halfScoreLabel("1ST", half: 0)
                halfScoreLabel("2ND", half: 1)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }

    private func halfScoreLabel(_ label: String, half: Int) -> some View {
        Text("\(label) \(score(for: match.homeTeamID, half: half))-\(score(for: match.awayTeamID, half: half))")
    }

    private var bipTimerPanel: some View {
        VStack(spacing: 6) {
            Text("BIP")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(bipState.elapsedText(at: context.date))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }

            Button {
                toggleBIP()
            } label: {
                Text(bipState.isRunning ? "停止" : "開始")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered)
            .disabled(!timeState.isRunning)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(bipState.isRunning ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Input target picker

    private var inputTeamPicker: some View {
        Picker("入力対象", selection: inputTeamSelection) {
            Text(teamName(for: match.homeTeamID)).tag(match.homeTeamID)
            Text(teamName(for: match.awayTeamID)).tag(match.awayTeamID)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Scoring row (1×4)

    private var scoringRow: some View {
        HStack(spacing: 8) {
            scoringButton(.tryScore)
            scoringButton(.conversion)
            scoringButton(.penaltyGoal)
            scoringButton(.dropGoal)
        }
    }

    // MARK: - Set piece compact (1 row per type)

    private var setPieceCompact: some View {
        VStack(spacing: 8) {
            V3SetPieceControl(
                title: "ラインアウト",
                category: "lineout",
                events: setPieceEvents,
                selectedTeamID: selectedInputTeam,
                onRecord: recordSetPiece
            )

            V3SetPieceControl(
                title: "スクラム",
                category: "scrum",
                events: setPieceEvents,
                selectedTeamID: selectedInputTeam,
                onRecord: recordSetPiece
            )
        }
    }

    // MARK: - Undo band

    private var undoBand: some View {
        Button {
            undoLastEvent()
        } label: {
            Text("取り消し")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(undoableLastEvent == nil)
    }

    // MARK: - Subviews

    private var kickResultPanel: some View {
        VStack(spacing: 14) {
            Text(pendingKickAttempt?.category.displayName ?? "キック")
                .font(.headline)
            HStack(spacing: 8) {
                Button {
                    recordPendingKick(outcome: "success")
                } label: {
                    Text("成功")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, minHeight: 86)
                        .background(Color.green.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.green, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    recordPendingKick(outcome: "fail")
                } label: {
                    Text("失敗")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 86)
                        .background(Color.red.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.red, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 12)
        .padding(.horizontal, 24)
    }

    private func scoringButton(_ category: ScoringCategory) -> some View {
        Button {
            recordScore(category)
        } label: {
            VStack(spacing: 2) {
                Text(category.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(countEvents(category: category.rawValue))")
                    .font(.title3.monospacedDigit())
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
    }

    private func teamTimerPanel(
        title: String,
        state: V3TimerState,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(state.elapsedText(at: context.date))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }

            Button {
                action()
            } label: {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(state.isRunning ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Timer toggling (unchanged from previous V3 behavior)

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
            savePossessionEvent(teamID: nil, outcome: "none", seconds: seconds)
        }
    }

    private func stopTeam1(at date: Date) {
        if let seconds = team1State.stop(at: date) {
            savePossessionEvent(teamID: match.homeTeamID, outcome: "own", seconds: seconds)
        }
    }

    private func stopTeam2(at date: Date) {
        if let seconds = team2State.stop(at: date) {
            savePossessionEvent(teamID: match.awayTeamID, outcome: "own", seconds: seconds)
        }
    }

    // MARK: - Event saving

    private func players(for event: StatEvent) -> [Player] {
        guard let teamID = event.teamID else { return selectedTeamPlayers }
        return players(forTeamID: teamID)
    }

    private func players(forTeamID teamID: UUID) -> [Player] {
        allPlayers
            .filter { $0.teamID == teamID }
            .sorted { $0.number < $1.number }
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
        if category.requiresResultSelection {
            pendingKickAttempt = PendingKickAttempt(
                category: category,
                teamID: selectedInputTeam,
                seconds: timeState.elapsedSeconds(at: Date()),
                half: currentHalf
            )
            isShowingKickPlayerSelection = true
            return
        }

        saveScoreEvent(category: category, outcome: "success", opensPlayerSheet: true)
    }

    private func recordPendingKick(outcome: String) {
        guard let attempt = pendingKickAttempt else { return }
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

    private func recordSetPiece(category: String, outcome: String) {
        let event = StatEvent(
            matchID: match.id,
            teamID: selectedInputTeam,
            category: category,
            outcome: outcome,
            seconds: timeState.elapsedSeconds(at: Date()),
            half: currentHalf
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func savePossessionEvent(teamID: UUID?, outcome: String, seconds: Int) {
        guard seconds > 0 else { return }

        let event = StatEvent(
            matchID: match.id,
            teamID: teamID,
            category: "possession",
            outcome: outcome,
            seconds: seconds,
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

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
    }
}

private struct V3SetPieceControl: View {
    let title: String
    let category: String
    let events: [StatEvent]
    let selectedTeamID: UUID
    let onRecord: (String, String) -> Void

    private var selectedEvents: [StatEvent] {
        events.filter { $0.category == category && $0.teamID == selectedTeamID }
    }

    private var successfulCount: Int {
        selectedEvents.filter { $0.outcome == "success" }.count
    }

    private var totalCount: Int {
        selectedEvents.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 96, alignment: .leading)

            Button("成功") {
                onRecord(category, "success")
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .buttonStyle(.borderedProminent)

            Button("失敗") {
                onRecord(category, "fail")
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .buttonStyle(.bordered)

            Text("\(successfulCount)/\(totalCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private struct PendingKickAttempt {
    let category: ScoringCategory
    let teamID: UUID
    let seconds: Int
    let half: Int
    var playerID: UUID?
    var hasSelectedPlayer = false
}

private struct V3TimerState {
    private var accumulatedSeconds = 0
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
        let intervalSeconds = max(0, Int(date.timeIntervalSince(startedAt)))
        accumulatedSeconds += intervalSeconds
        self.startedAt = nil
        return intervalSeconds
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
        guard let startedAt else {
            return accumulatedSeconds
        }
        return accumulatedSeconds + max(0, Int(date.timeIntervalSince(startedAt)))
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
        Substitution.self
    ], inMemory: true)
}
