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
    @State private var bipState = V3TimerState()

    var body: some View {
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

            Text("段階2: Time と BIP の2層。Time停止中はBIPも動けません。BIPを止めてもTimeは動き続けます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
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

    private func toggleTime() {
        let now = Date()
        if timeState.isRunning {
            timeState.stop(at: now)
            bipState.stop(at: now)
        } else {
            timeState.start(at: now)
        }
    }

    private func toggleBIP() {
        guard timeState.isRunning else { return }
        bipState.toggle(at: Date())
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
}
