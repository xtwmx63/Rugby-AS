//
//  PlayOrigin.swift
//  Rugby AS
//
//  攻撃(ポゼッション)やトライの「起点プレー」の種類。
//  StatEvent.origin に rawValue を保存し、表示はここの日本語名を使う。
//

import Foundation

enum PlayOrigin: String, CaseIterable, Identifiable {
    case scrum
    case lineout
    case turnover
    case kick
    case penalty
    case kickoff
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scrum: return "スクラム"
        case .lineout: return "ラインアウト"
        case .turnover: return "ターンオーバー"
        case .kick: return "キック処理"
        case .penalty: return "ペナルティ"
        case .kickoff: return "キックオフ"
        case .other: return "その他"
        }
    }

    /// 保存された rawValue から表示名を引く(不明値・nil は nil)
    static func displayName(for raw: String?) -> String? {
        raw.flatMap { PlayOrigin(rawValue: $0)?.displayName }
    }
}
