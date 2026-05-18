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
    @Query private var allEvents: [StatEvent]

    let match: Match

    @State private var timeState = V3TimerState()
    @State private var bipState = V3TimerState()
    @State private var team1State = V3TimerState()
    @State private var team2State = V3TimerState()
    @State private var selectedInputTeamID: UUID?

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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                timerPanel(title: "Time", state: timeState, fontSize: 54)

                Button {
                    toggleTime()
                } label: {
                    Text(timeState.isRunning ? "Time 停止" : "Time 開始")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)

                Divider()

                timerPanel(title: "BIP", state: bipState, fontSize: 42)

                Button {
                    toggleBIP()
                } label: {
                    Text(bipState.isRunning ? "BIP 停止" : "BIP 開始")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .disabled(!timeState.isRunning)

                Divider()

                HStack(spacing: 12) {
                    teamTimerPanel(
                        title: teamName(for: match.homeTeamID),
                        state: team1State,
                        buttonTitle: team1State.isRunning ? "Team1 停止" : "Team1 開始",
                        action: toggleTeam1
                    )

                    teamTimerPanel(
                        title: teamName(for: match.awayTeamID),
                        state: team2State,
                        buttonTitle: team2State.isRunning ? "Team2 停止" : "Team2 開始",
                        action: toggleTeam2
                    )
                }

                inputTeamSection
                scoringSection
                setPieceSection

                Text("V3時間機能はそのままに、得点とセットプレー入力を合流しています。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("V3 記録")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedInputTeamID == nil {
                selectedInputTeamID = match.homeTeamID
            }
        }
    }

    private var inputTeamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("入力対象")
                .font(.headline)

            Picker("入力対象", selection: inputTeamSelection) {
                Text(teamName(for: match.homeTeamID)).tag(match.homeTeamID)
                Text(teamName(for: match.awayTeamID)).tag(match.awayTeamID)
            }
            .pickerStyle(.segmented)

            Text("得点とセットプレーは \(teamName(for: selectedInputTeam)) の記録として保存します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("得点")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                scoringButton(.tryScore)
                scoringButton(.conversion)
                scoringButton(.penaltyGoal)
                scoringButton(.dropGoal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setPieceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("セットプレー")
                .font(.headline)

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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timerPanel(title: String, state: V3TimerState, fontSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(state.elapsedText(at: context.date))
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func scoringButton(_ category: ScoringCategory) -> some View {
        Button {
            recordScore(category)
        } label: {
            VStack(spacing: 4) {
                Text(category.displayName)
                    .font(.headline)
                Text("\(countEvents(category: category.rawValue))")
                    .font(.title3.monospacedDigit())
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.borderedProminent)
    }

    private func teamTimerPanel(
        title: String,
        state: V3TimerState,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(state.elapsedText(at: context.date))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }

            Button {
                action()
            } label: {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(state.isRunning ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(successfulCount)/\(totalCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("成功") {
                    onRecord(category, "success")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.borderedProminent)

                Button("失敗") {
                    onRecord(category, "fail")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
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
