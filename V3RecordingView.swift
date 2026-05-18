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
    @State private var isSecondHalf = false

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
    private var undoableLastEvent: StatEvent? {
        matchEvents
            .filter { $0.category != "possession" }
            .sorted { $0.seconds > $1.seconds }
            .first
    }

    var body: some View {
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
        .navigationTitle("V3 記録")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedInputTeamID == nil {
                selectedInputTeamID = match.homeTeamID
            }
        }
        .sheet(item: $scoringEventForPlayerSelection) { event in
            PlayerSelectionSheet(players: selectedTeamPlayers, title: "得点者を選択") { player in
                event.playerID = player?.id
                try? modelContext.save()
                scoringEventForPlayerSelection = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header band (Time / Score / Half)

    private var headerBand: some View {
        HStack(spacing: 10) {
            Text("Time")
                .font(.caption)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timeState.elapsedText(at: context.date))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
            }

            Button(timeState.isRunning ? "停止" : "開始") {
                toggleTime()
            }
            .buttonStyle(.borderedProminent)

            Spacer()

            Text("\(score(for: match.homeTeamID)) - \(score(for: match.awayTeamID))")
                .font(.system(size: 22, weight: .bold, design: .monospaced))

            Button(isSecondHalf ? "後半" : "前半") {
                isSecondHalf.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Possession band (Team1 / BIP / Team2)

    private var possessionBand: some View {
        HStack(spacing: 8) {
            teamTimerPanel(
                title: teamName(for: match.homeTeamID),
                state: team1State,
                buttonTitle: team1State.isRunning ? "停止" : "開始",
                action: toggleTeam1
            )

            bipTimerPanel

            teamTimerPanel(
                title: teamName(for: match.awayTeamID),
                state: team2State,
                buttonTitle: team2State.isRunning ? "停止" : "開始",
                action: toggleTeam2
            )
        }
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

    private func recordScore(_ category: ScoringCategory) {
        let event = StatEvent(
            matchID: match.id,
            teamID: selectedInputTeam,
            category: category.rawValue,
            outcome: "success",
            seconds: timeState.elapsedSeconds(at: Date())
        )
        modelContext.insert(event)
        try? modelContext.save()
        scoringEventForPlayerSelection = event
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
            seconds: timeState.elapsedSeconds(at: Date())
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
            seconds: seconds
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

    private func score(for teamID: UUID) -> Int {
        scoreEvents
            .filter { $0.teamID == teamID }
            .reduce(0) { partial, event in
                partial + scoreValue(for: event.category)
            }
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
