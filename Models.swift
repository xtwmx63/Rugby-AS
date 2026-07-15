//
//  Models.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import Foundation
import SwiftData

@Model
final class Team {
    @Attribute(.unique) var id: UUID
    var name: String
    // ロゴ画像のファイル名（ドキュメントディレクトリ配下）。nil で未設定。
    var logoPath: String?
    // チームカラーの 16 進カラーコード（"#RRGGBB"）。nil ならサマリー側で
    // HOME/AWAY 既定色（青/赤）にフォールバック。
    var colorHex: String?

    init(id: UUID = UUID(), name: String, logoPath: String? = nil, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
        self.colorHex = colorHex
    }
}

@Model
final class Player {
    @Attribute(.unique) var id: UUID
    var teamID: UUID
    // 背番号。nil = 背番号なし(試合に登録されていない選手など)。
    // 試合ごとの実際の番号はメンバー表(MatchLineup.number)に控えられる。
    var number: Int?
    var name: String?
    // 名前の読み(かな)。入力すると英語表記の自動生成に使う。
    var nameKana: String?
    // カードに載せる英語表記。読みから自動生成されるが、手動で上書きも可能。
    var nameRoman: String?
    // 顔写真のファイル名（ドキュメントディレクトリ配下）。nil で未設定。
    var imagePath: String?

    init(
        id: UUID = UUID(),
        teamID: UUID,
        number: Int?,
        name: String? = nil,
        nameKana: String? = nil,
        nameRoman: String? = nil,
        imagePath: String? = nil
    ) {
        self.id = id
        self.teamID = teamID
        self.number = number
        self.name = name
        self.nameKana = nameKana
        self.nameRoman = nameRoman
        self.imagePath = imagePath
    }
}

@Model
final class Tournament {
    @Attribute(.unique) var id: UUID
    var officialName: String

    init(id: UUID = UUID(), officialName: String) {
        self.id = id
        self.officialName = officialName
    }
}

@Model
final class Match {
    @Attribute(.unique) var id: UUID
    var tournamentID: UUID
    var homeTeamID: UUID
    var awayTeamID: UUID
    var playedAt: Date

    init(
        id: UUID = UUID(),
        tournamentID: UUID,
        homeTeamID: UUID,
        awayTeamID: UUID,
        playedAt: Date
    ) {
        self.id = id
        self.tournamentID = tournamentID
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.playedAt = playedAt
    }
}

@Model
final class StatEvent {
    @Attribute(.unique) var id: UUID
    var matchID: UUID
    var teamID: UUID?
    var playerID: UUID?
    var category: String
    var outcome: String
    var seconds: Int
    // ポゼッション/BIP など区間イベントの開始時刻。nil の既存データは duration から近似表示する。
    var startSeconds: Int?
    // 0 = 前半, 1 = 後半。既存データは default 0（前半）として扱う。
    var half: Int = 0

    init(
        id: UUID = UUID(),
        matchID: UUID,
        teamID: UUID? = nil,
        playerID: UUID? = nil,
        category: String,
        outcome: String,
        seconds: Int,
        startSeconds: Int? = nil,
        half: Int = 0
    ) {
        self.id = id
        self.matchID = matchID
        self.teamID = teamID
        self.playerID = playerID
        self.category = category
        self.outcome = outcome
        self.seconds = seconds
        self.startSeconds = startSeconds
        self.half = half
    }
}

@Model
final class MatchLineup {
    @Attribute(.unique) var id: UUID
    var matchID: UUID
    var teamID: UUID
    var playerID: UUID
    // "starter" / "reserve"
    var role: String
    // 表示順（同一 matchID × teamID × role 内で 0 から昇順）
    var order: Int
    // この試合で着ける背番号。nil なら選手の基本番号を使う。
    // (ラグビーは固定背番号を持たず試合ごとに変わるため、試合単位で持つ)
    var number: Int?

    init(
      id: UUID = UUID(),
        matchID: UUID,
        teamID: UUID,
        playerID: UUID,
        role: String,
        order: Int,
        number: Int? = nil
    ) {
        self.id = id
        self.matchID = matchID
        self.teamID = teamID
        self.playerID = playerID
        self.role = role
        self.order = order
        self.number = number
    }
}

@Model
final class Substitution {
    @Attribute(.unique) var id: UUID
    var matchID: UUID
    var playerInID: UUID
    var playerOutID: UUID
    var minute: Int
    // 0 = 前半, 1 = 後半。minute はそのハーフ内の経過分。
    // (StatEvent の half と同じ後付けカラム。既存データは前半扱い)
    var half: Int = 0

    init(
        id: UUID = UUID(),
        matchID: UUID,
        playerInID: UUID,
        playerOutID: UUID,
        minute: Int,
        half: Int = 0
    ) {
        self.id = id
        self.matchID = matchID
        self.playerInID = playerInID
        self.playerOutID = playerOutID
        self.minute = minute
        self.half = half
    }
}
