//
//  MatchNumbering.swift
//  Rugby AS
//
//  「この試合での背番号」を1箇所で解決するヘルパー。
//  ラグビーは固定背番号を持たないため、メンバー表(MatchLineup)に
//  試合ごとの番号を持ち、未設定なら選手の基本番号を使う。
//  番号を表示する画面はすべてここを通す(表示のばらつきを防ぐ)。
//

import Foundation
import SwiftData

enum MatchNumbering {
    /// 番号が未設定(チームページに追従する状態)のメンバー表に、
    /// 現在の背番号を書き込んで固定する(起動時に1回)。
    /// これをしないと、後からチームページで番号を変えたとき
    /// 過去の試合の背番号まで遡って変わってしまう。
    static func freezeLineupNumbers(context: ModelContext) {
        guard let lineups = try? context.fetch(FetchDescriptor<MatchLineup>()),
              let players = try? context.fetch(FetchDescriptor<Player>()) else {
            return
        }
        let playersByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })

        var didChange = false
        for entry in lineups where entry.number == nil {
            if let player = playersByID[entry.playerID] {
                entry.number = player.number
                didChange = true
            }
        }
        if didChange {
            try? context.save()
        }
    }

    /// その試合での背番号。メンバー表に試合用の番号があればそれ、なければ基本番号。
    static func number(for player: Player, matchID: UUID, lineups: [MatchLineup]) -> Int {
        lineups.first { $0.matchID == matchID && $0.playerID == player.id }?.number ?? player.number
    }

    /// 「#7 山田」形式の表示名(名前未登録なら番号のみ)
    static func label(for player: Player, matchID: UUID, lineups: [MatchLineup]) -> String {
        let number = number(for: player, matchID: matchID, lineups: lineups)
        if let name = player.name, !name.isEmpty {
            return "#\(number) \(name)"
        }
        return "#\(number)"
    }
}
