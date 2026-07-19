//
//  PlayOrigin.swift
//  Rugby AS
//
//  攻撃(ポゼッション)やトライの「起点プレー」の種類。
//  StatEvent.origin に rawValue を保存し、表示はここの日本語名を使う。
//

import Foundation

enum PlayOrigin: String, CaseIterable, Identifiable {
    case restart
    case scrum
    case lineout
    case tapKick = "tap_kick"
    case kick
    case turnover
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .restart: return "リスタート"
        case .scrum: return "スクラム"
        case .lineout: return "ラインアウト"
        case .tapKick: return "Tap Kick"
        case .kick: return "Kick"
        case .turnover: return "Turnover"
        case .other: return "他"
        }
    }

    // 記録画面のボタン用の略称。1行に7個並べてもタップしやすい大きさを保つため
    var shortName: String {
        switch self {
        case .restart: return "RS"
        case .scrum: return "SC"
        case .lineout: return "LO"
        case .tapKick: return "TAP"
        case .kick: return "KICK"
        case .turnover: return "TO"
        case .other: return "他"
        }
    }

    /// 保存された rawValue から表示名を引く(不明値・nil は nil)。
    /// 旧バージョンで保存した種類(kickoff/penalty)は近い項目へ寄せる。
    static func displayName(for raw: String?) -> String? {
        guard let raw else { return nil }
        if let origin = PlayOrigin(rawValue: raw) { return origin.displayName }
        switch raw {
        case "kickoff": return PlayOrigin.restart.displayName
        case "penalty": return PlayOrigin.tapKick.displayName
        default: return nil
        }
    }
}
