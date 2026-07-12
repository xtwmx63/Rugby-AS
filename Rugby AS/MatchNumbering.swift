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

enum MatchNumbering {
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
