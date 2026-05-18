//
//  V3RecordingView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/18.
//

import SwiftData
import SwiftUI

struct V3RecordingView: View {
    @Query private var teams: [Team]

    let match: Match

    @State private var timeState = V3TimerState()
    @State private var bipState = V3TimerState()
    @State private var team1State = V3TimerState()
    @State private var team2State = V3TimerState()

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

                Text("段階3-1: Team1/Team2 を追加。どちらかを開始すると、もう片方は停止します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("V3 記録")
        .navigationBarTitleDisplayMode(.inline)
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
            timeState.stop(at: now)
            bipState.stop(at: now)
            team1State.stop(at: now)
            team2State.stop(at: now)
        } else {
            timeState.start(at: now)
        }
    }

    private func toggleBIP() {
        guard timeState.isRunning else { return }
        let now = Date()
        if bipState.isRunning {
            bipState.stop(at: now)
            team1State.stop(at: now)
            team2State.stop(at: now)
        } else {
            bipState.start(at: now)
        }
    }

    private func toggleTeam1() {
        let now = Date()
        ensureTimeAndBIPRunning(at: now)
        if team1State.isRunning {
            team1State.stop(at: now)
        } else {
            team2State.stop(at: now)
            team1State.start(at: now)
        }
    }

    private func toggleTeam2() {
        let now = Date()
        ensureTimeAndBIPRunning(at: now)
        if team2State.isRunning {
            team2State.stop(at: now)
        } else {
            team1State.stop(at: now)
            team2State.start(at: now)
        }
    }

    private func ensureTimeAndBIPRunning(at date: Date) {
        timeState.start(at: date)
        bipState.start(at: date)
    }

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
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
            stop(at: date)
        } else {
            start(at: date)
        }
    }

    mutating func start(at date: Date) {
        guard !isRunning else { return }
        startedAt = date
    }

    mutating func stop(at date: Date) {
        guard isRunning else { return }
        accumulatedSeconds = elapsedSeconds(at: date)
        startedAt = nil
    }

    func elapsedText(at date: Date) -> String {
        let seconds = elapsedSeconds(at: date)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func elapsedSeconds(at date: Date) -> Int {
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
