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
    // メンバー表に載っていないのに記録に登場した選手の「番号の控え」に使う役割名。
    // メンバー登録画面には表示されない(starter/reserveのみ表示するため)。
    static let numberSnapshotRole = "number_snapshot"

    /// 全試合の背番号を「その時点の番号」で固定する(起動時に1回)。
    /// これをしないと、後からチームページで番号を変えたとき
    /// 過去の試合の背番号まで遡って変わってしまう。
    static func freezeLineupNumbers(context: ModelContext) {
        freezeNumbers(matchIDs: nil, context: context)
    }

    /// 特定の試合だけ背番号を固定する(記録画面を閉じたとき等に呼ぶ)
    static func freezeNumbers(forMatch matchID: UUID, context: ModelContext) {
        freezeNumbers(matchIDs: [matchID], context: context)
    }

    private static func freezeNumbers(matchIDs: Set<UUID>?, context: ModelContext) {
        guard let lineups = try? context.fetch(FetchDescriptor<MatchLineup>()),
              let players = try? context.fetch(FetchDescriptor<Player>()),
              let events = try? context.fetch(FetchDescriptor<StatEvent>()),
              let substitutions = try? context.fetch(FetchDescriptor<Substitution>()) else {
            return
        }
        let playersByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        var didChange = false

        func isTargetMatch(_ id: UUID) -> Bool {
            matchIDs == nil || matchIDs?.contains(id) == true
        }

        // 1) メンバー表にあるが番号未設定の行に、現在の番号を書き込む
        //    (背番号なしの選手はそのまま=書き込むものがない)
        for entry in lineups where entry.number == nil && isTargetMatch(entry.matchID) {
            if let number = playersByID[entry.playerID]?.number {
                entry.number = number
                didChange = true
            }
        }

        // 2) メンバー表に載っていないのに得点・交代の記録に登場する選手には、
        //    「番号の控え」の行を作って現在の番号を残す
        //    (メンバー表未登録の試合でも、過去の背番号が変わらないように)
        var knownPairs: Set<String> = Set(lineups.map { "\($0.matchID)|\($0.playerID)" })

        var appearingPairs: [(matchID: UUID, playerID: UUID)] = []
        for event in events {
            if let playerID = event.playerID, isTargetMatch(event.matchID) {
                appearingPairs.append((event.matchID, playerID))
            }
        }
        for substitution in substitutions where isTargetMatch(substitution.matchID) {
            appearingPairs.append((substitution.matchID, substitution.playerInID))
            appearingPairs.append((substitution.matchID, substitution.playerOutID))
        }

        for pair in appearingPairs {
            let key = "\(pair.matchID)|\(pair.playerID)"
            guard !knownPairs.contains(key),
                  let player = playersByID[pair.playerID],
                  let number = player.number else {
                continue
            }
            knownPairs.insert(key)
            context.insert(MatchLineup(
                matchID: pair.matchID,
                teamID: player.teamID,
                playerID: pair.playerID,
                role: numberSnapshotRole,
                order: 0,
                number: number
            ))
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }

    /// その試合での背番号。メンバー表に試合用の番号があればそれ、なければ基本番号。
    /// nil = 背番号なし。
    static func number(for player: Player, matchID: UUID, lineups: [MatchLineup]) -> Int? {
        lineups.first { $0.matchID == matchID && $0.playerID == player.id }?.number ?? player.number
    }

    /// 「#7」形式の番号表示。背番号なしは「ー」
    static func numberText(_ number: Int?) -> String {
        number.map { "#\($0)" } ?? "ー"
    }

    /// その試合での「#7」表示(背番号なしは「ー」)
    static func numberLabel(for player: Player, matchID: UUID, lineups: [MatchLineup]) -> String {
        numberText(number(for: player, matchID: matchID, lineups: lineups))
    }

    /// 「#7 山田」形式の表示名。番号なしなら名前のみ、両方なければ「名前未設定」
    static func label(for player: Player, matchID: UUID, lineups: [MatchLineup]) -> String {
        let number = number(for: player, matchID: matchID, lineups: lineups)
        let name = (player.name?.isEmpty == false) ? player.name : nil
        switch (number, name) {
        case (let number?, let name?): return "#\(number) \(name)"
        case (nil, let name?): return name
        case (let number?, nil): return "#\(number)"
        case (nil, nil): return "名前未設定"
        }
    }
}
