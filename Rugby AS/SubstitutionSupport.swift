//
//  SubstitutionSupport.swift
//  Rugby AS
//
//  交代の記録と出場時間の自動計算。
//
//  出場時間の考え方:
//  - スタメン(メンバー表のstarter)は試合開始から出場。
//  - 交代で下がったら区間を閉じ、入った選手は新しい区間を開く。
//  - ハーフの長さは実際の記録(StatEventや交代)の最終時刻から求める
//    (形式を決め打ちしない、このアプリの基本方針)。
//  - スタメンが未登録の試合は正確に計算できないので「計算不可」として扱う。
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - 出場時間の計算

enum PlayingTimeCalculator {

    struct Result {
        // 選手ID → 出場分数。スタメン未登録なら空。
        var minutesByPlayer: [UUID: Int] = [:]
        // スタメン情報があったか(falseなら「計算不可」と表示する)
        var hasStarterInfo = false
        // 試合全体の長さ(分)。表示の分母に使える
        var totalMinutes = 0
    }

    static func calculate(
        matchID: UUID,
        lineups: [MatchLineup],
        substitutions: [Substitution],
        events: [StatEvent]
    ) -> Result {
        let starters = lineups
            .filter { $0.matchID == matchID && $0.role == "starter" }
            .map(\.playerID)
        let matchSubstitutions = substitutions
            .filter { $0.matchID == matchID }
        let matchEvents = events
            .filter { $0.matchID == matchID && $0.category != "match_state" }

        guard !starters.isEmpty else {
            return Result()
        }

        // 各ハーフの長さ(分)。記録と交代の遅い方まで含めて切り上げる
        let firstHalfMinutes = halfMinutes(half: 0, events: matchEvents, substitutions: matchSubstitutions)
        let secondHalfMinutes = halfMinutes(half: 1, events: matchEvents, substitutions: matchSubstitutions)
        let totalMinutes = firstHalfMinutes + secondHalfMinutes

        // 交代を通算の分に直して時系列に並べる
        let orderedSubstitutions = matchSubstitutions
            .map { substitution -> (absoluteMinute: Int, substitution: Substitution) in
                let base = substitution.half >= 1 ? firstHalfMinutes : 0
                let clampedMinute = min(
                    max(0, substitution.minute),
                    substitution.half >= 1 ? secondHalfMinutes : firstHalfMinutes
                )
                return (base + clampedMinute, substitution)
            }
            .sorted { $0.absoluteMinute < $1.absoluteMinute }

        // スタメンは0分から出場。交代のたびに区間を閉じ/開きする
        var enteredAtMinute: [UUID: Int] = [:]
        var minutesByPlayer: [UUID: Int] = [:]
        for starter in starters {
            enteredAtMinute[starter] = 0
        }

        for entry in orderedSubstitutions {
            let substitution = entry.substitution
            // 下がる選手: 出場中のときだけ区間を閉じる(入力ミスに寛容に)
            if let entered = enteredAtMinute.removeValue(forKey: substitution.playerOutID) {
                minutesByPlayer[substitution.playerOutID, default: 0] += max(0, entry.absoluteMinute - entered)
            }
            // 入る選手: まだ出場していないときだけ区間を開く
            if enteredAtMinute[substitution.playerInID] == nil {
                enteredAtMinute[substitution.playerInID] = entry.absoluteMinute
            }
        }

        // 試合終了時点で出場中の選手の区間を閉じる
        for (playerID, entered) in enteredAtMinute {
            minutesByPlayer[playerID, default: 0] += max(0, totalMinutes - entered)
        }

        return Result(
            minutesByPlayer: minutesByPlayer,
            hasStarterInfo: true,
            totalMinutes: totalMinutes
        )
    }

    private static func halfMinutes(
        half: Int,
        events: [StatEvent],
        substitutions: [Substitution]
    ) -> Int {
        let maxEventSecond = events
            .filter { $0.half == half }
            .map { event -> Int in
                if event.category == "possession" {
                    return (event.startSeconds ?? 0) + event.seconds
                }
                return event.seconds
            }
            .max() ?? 0
        let maxSubstitutionMinute = substitutions
            .filter { $0.half == half }
            .map(\.minute)
            .max() ?? 0

        let eventMinutes = Int(ceil(Double(maxEventSecond) / 60.0))
        let minutes = max(eventMinutes, maxSubstitutionMinute)
        // 前半は記録がなくても最低1分にする(0除算や0分試合を避ける)
        return half == 0 ? max(1, minutes) : minutes
    }
}

// MARK: - 交代の入力シート(記録画面とサマリーの両方から使う)

struct SubstitutionAddSheet: View {
    let match: Match
    let teams: [Team]
    let players: [Player]
    // この試合のメンバー表(試合ごとの背番号の表示に使う)
    var lineups: [MatchLineup] = []
    let initialHalf: Int
    let initialMinute: Int
    // (下がる選手, 入る選手, 前後半, 分)
    let onAdd: (UUID, UUID, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeamID: UUID?
    @State private var playerOutID: UUID?
    @State private var playerInID: UUID?
    @State private var half: Int = 0
    @State private var minute: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("チーム") {
                    Picker("チーム", selection: $selectedTeamID) {
                        Text(teamName(for: match.homeTeamID)).tag(Optional(match.homeTeamID))
                        Text(teamName(for: match.awayTeamID)).tag(Optional(match.awayTeamID))
                    }
                    .pickerStyle(.segmented)
                }

                Section("交代") {
                    Picker("OUT(下がる選手)", selection: $playerOutID) {
                        Text("選択してください").tag(UUID?.none)
                        ForEach(teamPlayers) { player in
                            Text(playerLabel(player)).tag(Optional(player.id))
                        }
                    }
                    Picker("IN(入る選手)", selection: $playerInID) {
                        Text("選択してください").tag(UUID?.none)
                        ForEach(teamPlayers) { player in
                            Text(playerLabel(player)).tag(Optional(player.id))
                        }
                    }
                }

                Section("時間") {
                    Picker("前後半", selection: $half) {
                        Text("前半").tag(0)
                        Text("後半").tag(1)
                    }
                    .pickerStyle(.segmented)

                    Stepper("\(minute)分", value: $minute, in: 0...120)
                }

                Section {
                    Button("交代を記録") {
                        submit()
                    }
                    .font(.headline)
                    .disabled(!canSubmit)
                } footer: {
                    if let playerOutID, playerOutID == playerInID {
                        Text("OUTとINに同じ選手は選べません。")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("交代を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if selectedTeamID == nil {
                    selectedTeamID = match.homeTeamID
                    half = initialHalf
                    minute = initialMinute
                }
            }
            .onChange(of: selectedTeamID) { _, _ in
                playerOutID = nil
                playerInID = nil
            }
        }
    }

    private var teamPlayers: [Player] {
        players
            .filter { $0.teamID == selectedTeamID }
            .sorted {
                MatchNumbering.number(for: $0, matchID: match.id, lineups: lineups)
                    < MatchNumbering.number(for: $1, matchID: match.id, lineups: lineups)
            }
    }

    private var canSubmit: Bool {
        guard let playerOutID, let playerInID else { return false }
        return playerOutID != playerInID
    }

    private func submit() {
        guard let playerOutID, let playerInID, playerOutID != playerInID else { return }
        onAdd(playerOutID, playerInID, half, minute)
        dismiss()
    }

    private func teamName(for teamID: UUID) -> String {
        teams.first { $0.id == teamID }?.name ?? "チーム未設定"
    }

    private func playerLabel(_ player: Player) -> String {
        MatchNumbering.label(for: player, matchID: match.id, lineups: lineups)
    }
}
