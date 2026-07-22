//
//  TournamentMeta.swift
//  Rugby AS
//
//  大会の「7人制/15人制」と「フォーマット」の語彙。
//  Tournament には rawValue を保存し、表示はここの日本語名を使う。
//  どちらも任意(nil = 未設定)。
//

import Foundation

enum RugbyVariant: String, CaseIterable, Identifiable {
    case sevens
    case fifteens

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sevens: return "7人制"
        case .fifteens: return "15人制"
        }
    }

    static func displayName(for raw: String?) -> String? {
        raw.flatMap { RugbyVariant(rawValue: $0)?.displayName }
    }
}

enum TournamentFormat: String, CaseIterable, Identifiable {
    case league            // 総当り(リーグ戦)
    case knockout          // 勝ち抜きトーナメント
    case poolThenKnockout  // 予選プール + 決勝トーナメント
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .league: return "総当り(リーグ)"
        case .knockout: return "トーナメント"
        case .poolThenKnockout: return "予選プール+決勝T"
        case .other: return "その他"
        }
    }

    static func displayName(for raw: String?) -> String? {
        raw.flatMap { TournamentFormat(rawValue: $0)?.displayName }
    }
}
