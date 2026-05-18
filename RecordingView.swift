//
//  RecordingView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import SwiftData
import SwiftUI

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query private var allEvents: [StatEvent]

    let match: Match

    @State private var activeStartedAt: Date?
    @State private var accumulatedElapsedSeconds = 0
    @State private var timeControlState = TimeControlState.notStarted
    @State private var selectedHalf = "前半"
    @State private var currentPossession: PossessionSide?
    @State private var possessionStartedAt: Date?
    @State private var lastEventID: UUID?
    @State private var scoringEventForPlayerSelection: StatEvent?
    @State private var finishAlertIsPresented = false

    private let halves = ["前半", "後半"]

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

    private var matchEvents: [StatEvent] {
        allEvents.filter { $0.matchID == match.id }
    }

    private var scoreEvents: [StatEvent] {
        matchEvents.filter { ScoringCategory(rawValue: $0.category) != nil }
    }

    private var setPieceEvents: [StatEvent] {
        matchEvents.filter { $0.category == "lineout" || $0.category == "scrum" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                possessionSection
                scoringSection
                setPieceSection
                undoSection
            }
            .padding()
        }
        .navigationTitle("記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("試合終了") {
                    finishAlertIsPresented = true
                }
            }
        }
        .sheet(item: $scoringEventForPlayerSelection) { event in
            PlayerSelectionSheet(players: players, title: "得点者を選択") { player in
                event.playerID = player?.id
                try? modelContext.save()
                scoringEventForPlayerSelection = nil
            }
            .presentationDetents([.medium, .large])
        }
        .alert("試合を終了しますか？", isPresented: $finishAlertIsPresented) {
            Button("キャンセル", role: .cancel) {}
            Button("終了", role: .destructive) {
                finishMatch()
            }
        } message: {
            Text("計測中のポゼッションがあれば、最後の区間として保存します。")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsedText(at: context.date))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }

            Picker("ハーフ", selection: $selectedHalf) {
                ForEach(halves, id: \.self) { half in
                    Text(half).tag(half)
                }
            }
            .pickerStyle(.segmented)

            timeControlButtons
        }
    }

    private var timeControlButtons: some View {
        HStack(spacing: 12) {
            Button("開始") {
                startTiming()
            }
            .buttonStyle(.borderedProminent)
            .disabled(timeControlState != .notStarted)

            Button("一時停止") {
                pauseTiming()
            }
            .buttonStyle(.bordered)
            .disabled(timeControlState != .running)

            Button("再開") {
                resumeTiming()
            }
            .buttonStyle(.borderedProminent)
            .disabled(timeControlState != .paused)
        }
    }

    private var possessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ポゼッション")
                .font(.headline)

            HStack(spacing: 12) {
                possessionButton(title: "自チーム", side: .own)
                possessionButton(title: "相手", side: .opponent)
            }

            Text(currentPossessionText)
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

            SetPieceControl(
                title: "ラインアウト",
                category: "lineout",
                events: setPieceEvents,
                onRecord: recordSetPiece
            )

            SetPieceControl(
                title: "スクラム",
                category: "scrum",
                events: setPieceEvents,
                onRecord: recordSetPiece
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var undoSection: some View {
        Button(role: .destructive) {
            undoLastEvent()
        } label: {
            Label("取り消し", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(lastEventID == nil)
    }

    private var currentPossessionText: String {
        switch timeControlState {
        case .notStarted:
            return "開始を押すまで計測しません。"
        case .paused:
            return "一時停止中はどちらのポゼッションにも含めません。"
        case .running:
            guard let currentPossession else {
                return "自チームか相手をタップした時点から保持を記録します。"
            }
            return "現在: \(currentPossession.displayName)"
        }
    }

    private func possessionButton(title: String, side: PossessionSide) -> some View {
        Button {
            switchPossession(to: side)
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(currentPossession == side ? .blue : .gray)
        .disabled(timeControlState != .running)
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
            .frame(maxWidth: .infinity, minHeight: 74)
        }
        .buttonStyle(.borderedProminent)
    }

    private func switchPossession(to side: PossessionSide) {
        guard timeControlState == .running else { return }

        guard currentPossession != side else { return }

        let now = Date()
        closeCurrentPossession(at: now)
        currentPossession = side
        possessionStartedAt = now
    }

    private func recordScore(_ category: ScoringCategory) {
        saveEvent(
            category: category.rawValue,
            outcome: "success",
            seconds: elapsedSeconds(),
            opensPlayerSheet: true
        )
    }

    private func recordSetPiece(category: String, outcome: String) {
        saveEvent(
            category: category,
            outcome: outcome,
            seconds: elapsedSeconds(),
            opensPlayerSheet: false
        )
    }

    private func startTiming() {
        accumulatedElapsedSeconds = 0
        activeStartedAt = Date()
        currentPossession = nil
        possessionStartedAt = nil
        timeControlState = .running
    }

    private func pauseTiming() {
        guard timeControlState == .running else { return }

        let now = Date()
        closeCurrentPossession(at: now)
        updateAccumulatedElapsedSeconds(at: now)
        currentPossession = nil
        possessionStartedAt = nil
        activeStartedAt = nil
        timeControlState = .paused
        saveEvent(category: "possession", outcome: "none", seconds: 0, opensPlayerSheet: false)
    }

    private func resumeTiming() {
        guard timeControlState == .paused else { return }

        activeStartedAt = Date()
        currentPossession = nil
        possessionStartedAt = nil
        timeControlState = .running
    }

    private func closeCurrentPossession(at date: Date) {
        guard let currentPossession, let possessionStartedAt else { return }

        saveEvent(
            category: "possession",
            outcome: currentPossession.rawValue,
            seconds: max(1, Int(date.timeIntervalSince(possessionStartedAt))),
            opensPlayerSheet: false
        )
    }

    private func updateAccumulatedElapsedSeconds(at date: Date) {
        guard let activeStartedAt else { return }
        accumulatedElapsedSeconds += max(0, Int(date.timeIntervalSince(activeStartedAt)))
    }

    private func saveEvent(category: String, outcome: String, seconds: Int, opensPlayerSheet: Bool) {
        let event = StatEvent(matchID: match.id, category: category, outcome: outcome, seconds: seconds)
        modelContext.insert(event)
        lastEventID = event.id
        try? modelContext.save()

        if opensPlayerSheet {
            scoringEventForPlayerSelection = event
        }
    }

    private func undoLastEvent() {
        guard let lastEventID, let event = matchEvents.first(where: { $0.id == lastEventID }) else {
            self.lastEventID = nil
            return
        }

        if event.category == "possession", let side = PossessionSide(rawValue: event.outcome), timeControlState == .running {
            currentPossession = side
            possessionStartedAt = Date()
        }

        modelContext.delete(event)
        self.lastEventID = nil
        try? modelContext.save()
    }

    private func finishMatch() {
        let now = Date()
        if timeControlState == .running {
            closeCurrentPossession(at: now)
            updateAccumulatedElapsedSeconds(at: now)
        }

        currentPossession = nil
        possessionStartedAt = nil
        activeStartedAt = nil
        timeControlState = .paused
        saveEvent(category: "match_state", outcome: "finished", seconds: elapsedSeconds(), opensPlayerSheet: false)
        dismiss()
    }

    private func countEvents(category: String) -> Int {
        scoreEvents.filter { $0.category == category }.count
    }

    private func elapsedSeconds() -> Int {
        activeElapsedSeconds(at: Date())
    }

    private func elapsedText(at date: Date) -> String {
        let seconds = activeElapsedSeconds(at: date)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func activeElapsedSeconds(at date: Date) -> Int {
        guard timeControlState == .running, let activeStartedAt else {
            return accumulatedElapsedSeconds
        }
        return accumulatedElapsedSeconds + max(0, Int(date.timeIntervalSince(activeStartedAt)))
    }
}

private enum TimeControlState {
    case notStarted
    case running
    case paused
}

private enum PossessionSide: String {
    case own
    case opponent

    var displayName: String {
        switch self {
        case .own:
            return "自チーム"
        case .opponent:
            return "相手"
        }
    }
}

enum ScoringCategory: String {
    case tryScore = "try"
    case conversion = "conversion"
    case penaltyGoal = "penalty_goal"
    case dropGoal = "drop_goal"

    var displayName: String {
        switch self {
        case .tryScore:
            return "トライ"
        case .conversion:
            return "コンバージョン"
        case .penaltyGoal:
            return "PG"
        case .dropGoal:
            return "DG"
        }
    }
}

private struct SetPieceControl: View {
    let title: String
    let category: String
    let events: [StatEvent]
    let onRecord: (String, String) -> Void

    private var successfulCount: Int {
        events.filter { $0.category == category && $0.outcome == "success" }.count
    }

    private var totalCount: Int {
        events.filter { $0.category == category }.count
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

#Preview {
    NavigationStack {
        RecordingView(match: Match(tournamentID: UUID(), homeTeamID: UUID(), awayTeamID: UUID(), playedAt: Date()))
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
