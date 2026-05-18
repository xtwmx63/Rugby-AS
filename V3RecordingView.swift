//
//  V3RecordingView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/18.
//

import SwiftUI

struct V3RecordingView: View {
    let match: Match

    @State private var timeState = V3TimerState()

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Time")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timeState.elapsedText(at: context.date))
                        .font(.system(size: 54, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
            }

            Button {
                timeState.toggle(at: Date())
            } label: {
                Text(timeState.isRunning ? "Time 停止" : "Time 開始")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)

            Text("段階1: Time タイマー単体。BIP と Team1/Team2 はまだ追加していません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("V3 記録")
        .navigationBarTitleDisplayMode(.inline)
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

    func elapsedText(at date: Date) -> String {
        let seconds = elapsedSeconds(at: date)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private mutating func start(at date: Date) {
        startedAt = date
    }

    private mutating func stop(at date: Date) {
        accumulatedSeconds = elapsedSeconds(at: date)
        startedAt = nil
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
}
