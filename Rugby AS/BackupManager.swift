//
//  BackupManager.swift
//  Rugby AS
//
//  全記録のバックアップ(書き出し/読み込み)。
//  チーム・選手・大会・試合・記録・メンバー表と、選手写真/ロゴ、
//  試合時間設定、デフォルト自チーム名を1つのJSONファイルにまとめる。
//  動画ファイルはサイズが大きすぎるため含めない(再取り込みで復元する)。
//
//  読み込みは「合体」方式: 同じID
//  のデータは上書き、無いものは追加。削除は絶対にしない。
//  何度読み込んでも壊れない(機種変更・二重読み込みに安全)。
//

import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - バックアップファイルの中身(JSONの形)

struct BackupFile: Codable {
    var formatVersion: Int = 1
    var exportedAt: Date
    var defaultTeamName: String?
    // 試合時間設定(matchClockSettingsByMatchID)の保存内容をそのまま持つ
    var matchClockSettingsRaw: Data?
    var teams: [BackupTeam]
    var players: [BackupPlayer]
    var tournaments: [BackupTournament]
    var matches: [BackupMatch]
    var statEvents: [BackupStatEvent]
    var matchLineups: [BackupMatchLineup]
    var substitutions: [BackupSubstitution]
}

struct BackupTeam: Codable {
    var id: UUID
    var name: String
    var colorHex: String?
    var logoImageBase64: String?
}

struct BackupPlayer: Codable {
    var id: UUID
    var teamID: UUID
    var number: Int
    var name: String?
    var imageBase64: String?
}

struct BackupTournament: Codable {
    var id: UUID
    var officialName: String
}

struct BackupMatch: Codable {
    var id: UUID
    var tournamentID: UUID
    var homeTeamID: UUID
    var awayTeamID: UUID
    var playedAt: Date
}

struct BackupStatEvent: Codable {
    var id: UUID
    var matchID: UUID
    var teamID: UUID?
    var playerID: UUID?
    var category: String
    var outcome: String
    var seconds: Int
    var startSeconds: Int?
    var half: Int
}

struct BackupMatchLineup: Codable {
    var id: UUID
    var matchID: UUID
    var teamID: UUID
    var playerID: UUID
    var role: String
    var order: Int
}

struct BackupSubstitution: Codable {
    var id: UUID
    var matchID: UUID
    var playerInID: UUID
    var playerOutID: UUID
    var minute: Int
}

// 読み込み結果の件数(画面に表示する)
struct BackupRestoreSummary {
    var teams = 0
    var players = 0
    var tournaments = 0
    var matches = 0
    var statEvents = 0
    var matchLineups = 0
    var substitutions = 0

    var message: String {
        "チーム\(teams)件・選手\(players)件・大会\(tournaments)件・試合\(matches)件・記録\(statEvents)件を読み込みました。"
    }
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "このバックアップ(形式\(version))は、より新しいバージョンのアプリで作られています。アプリを更新してから読み込んでください。"
        case .unreadableFile:
            return "バックアップファイルを読み取れませんでした。Rugby ASで書き出したファイルか確認してください。"
        }
    }
}

// MARK: - 書き出し/読み込みの本体

enum BackupManager {
    private static let clockSettingsKey = "matchClockSettingsByMatchID"
    private static let defaultTeamNameKey = "defaultTeamName"

    // 全データを集めてJSONにする
    static func makeBackupData(context: ModelContext) throws -> Data {
        let teams = try context.fetch(FetchDescriptor<Team>())
        let players = try context.fetch(FetchDescriptor<Player>())
        let tournaments = try context.fetch(FetchDescriptor<Tournament>())
        let matches = try context.fetch(FetchDescriptor<Match>())
        let statEvents = try context.fetch(FetchDescriptor<StatEvent>())
        let lineups = try context.fetch(FetchDescriptor<MatchLineup>())
        let substitutions = try context.fetch(FetchDescriptor<Substitution>())

        let backup = BackupFile(
            exportedAt: Date(),
            defaultTeamName: UserDefaults.standard.string(forKey: defaultTeamNameKey),
            matchClockSettingsRaw: UserDefaults.standard.data(forKey: clockSettingsKey),
            teams: teams.map { team in
                BackupTeam(
                    id: team.id,
                    name: team.name,
                    colorHex: team.colorHex,
                    logoImageBase64: imageBase64(named: team.logoPath)
                )
            },
            players: players.map { player in
                BackupPlayer(
                    id: player.id,
                    teamID: player.teamID,
                    number: player.number,
                    name: player.name,
                    imageBase64: imageBase64(named: player.imagePath)
                )
            },
            tournaments: tournaments.map { BackupTournament(id: $0.id, officialName: $0.officialName) },
            matches: matches.map {
                BackupMatch(
                    id: $0.id,
                    tournamentID: $0.tournamentID,
                    homeTeamID: $0.homeTeamID,
                    awayTeamID: $0.awayTeamID,
                    playedAt: $0.playedAt
                )
            },
            statEvents: statEvents.map {
                BackupStatEvent(
                    id: $0.id,
                    matchID: $0.matchID,
                    teamID: $0.teamID,
                    playerID: $0.playerID,
                    category: $0.category,
                    outcome: $0.outcome,
                    seconds: $0.seconds,
                    startSeconds: $0.startSeconds,
                    half: $0.half
                )
            },
            matchLineups: lineups.map {
                BackupMatchLineup(
                    id: $0.id,
                    matchID: $0.matchID,
                    teamID: $0.teamID,
                    playerID: $0.playerID,
                    role: $0.role,
                    order: $0.order
                )
            },
            substitutions: substitutions.map {
                BackupSubstitution(
                    id: $0.id,
                    matchID: $0.matchID,
                    playerInID: $0.playerInID,
                    playerOutID: $0.playerOutID,
                    minute: $0.minute
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // JSONを読み込んで合体させる(同じIDは上書き・無いものは追加・削除しない)
    @discardableResult
    static func restore(from data: Data, context: ModelContext) throws -> BackupRestoreSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(BackupFile.self, from: data) else {
            throw BackupError.unreadableFile
        }
        guard backup.formatVersion <= 1 else {
            throw BackupError.unsupportedVersion(backup.formatVersion)
        }

        var summary = BackupRestoreSummary()

        // チーム
        let existingTeams = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Team>()).map { ($0.id, $0) }
        )
        for item in backup.teams {
            let logoPath = savedImageName(fromBase64: item.logoImageBase64)
            if let existing = existingTeams[item.id] {
                existing.name = item.name
                existing.colorHex = item.colorHex
                if let logoPath {
                    // 新しい写真に差し替えるときは、古いファイルを消して二重を防ぐ
                    if let oldPath = existing.logoPath { ImageStorage.delete(named: oldPath) }
                    existing.logoPath = logoPath
                }
            } else {
                context.insert(Team(id: item.id, name: item.name, logoPath: logoPath, colorHex: item.colorHex))
            }
            summary.teams += 1
        }

        // 選手
        let existingPlayers = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Player>()).map { ($0.id, $0) }
        )
        for item in backup.players {
            let imagePath = savedImageName(fromBase64: item.imageBase64)
            if let existing = existingPlayers[item.id] {
                existing.teamID = item.teamID
                existing.number = item.number
                existing.name = item.name
                if let imagePath {
                    if let oldPath = existing.imagePath { ImageStorage.delete(named: oldPath) }
                    existing.imagePath = imagePath
                }
            } else {
                context.insert(Player(id: item.id, teamID: item.teamID, number: item.number, name: item.name, imagePath: imagePath))
            }
            summary.players += 1
        }

        // 大会
        let existingTournaments = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Tournament>()).map { ($0.id, $0) }
        )
        for item in backup.tournaments {
            if let existing = existingTournaments[item.id] {
                existing.officialName = item.officialName
            } else {
                context.insert(Tournament(id: item.id, officialName: item.officialName))
            }
            summary.tournaments += 1
        }

        // 試合
        let existingMatches = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Match>()).map { ($0.id, $0) }
        )
        for item in backup.matches {
            if let existing = existingMatches[item.id] {
                existing.tournamentID = item.tournamentID
                existing.homeTeamID = item.homeTeamID
                existing.awayTeamID = item.awayTeamID
                existing.playedAt = item.playedAt
            } else {
                context.insert(Match(
                    id: item.id,
                    tournamentID: item.tournamentID,
                    homeTeamID: item.homeTeamID,
                    awayTeamID: item.awayTeamID,
                    playedAt: item.playedAt
                ))
            }
            summary.matches += 1
        }

        // 記録(スタッツ)
        let existingEvents = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<StatEvent>()).map { ($0.id, $0) }
        )
        for item in backup.statEvents {
            if let existing = existingEvents[item.id] {
                existing.matchID = item.matchID
                existing.teamID = item.teamID
                existing.playerID = item.playerID
                existing.category = item.category
                existing.outcome = item.outcome
                existing.seconds = item.seconds
                existing.startSeconds = item.startSeconds
                existing.half = item.half
            } else {
                context.insert(StatEvent(
                    id: item.id,
                    matchID: item.matchID,
                    teamID: item.teamID,
                    playerID: item.playerID,
                    category: item.category,
                    outcome: item.outcome,
                    seconds: item.seconds,
                    startSeconds: item.startSeconds,
                    half: item.half
                ))
            }
            summary.statEvents += 1
        }

        // メンバー表
        let existingLineups = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<MatchLineup>()).map { ($0.id, $0) }
        )
        for item in backup.matchLineups {
            if let existing = existingLineups[item.id] {
                existing.matchID = item.matchID
                existing.teamID = item.teamID
                existing.playerID = item.playerID
                existing.role = item.role
                existing.order = item.order
            } else {
                context.insert(MatchLineup(
                    id: item.id,
                    matchID: item.matchID,
                    teamID: item.teamID,
                    playerID: item.playerID,
                    role: item.role,
                    order: item.order
                ))
            }
            summary.matchLineups += 1
        }

        // 交代(V2用の器。あれば持ち込む)
        let existingSubstitutions = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Substitution>()).map { ($0.id, $0) }
        )
        for item in backup.substitutions {
            if let existing = existingSubstitutions[item.id] {
                existing.matchID = item.matchID
                existing.playerInID = item.playerInID
                existing.playerOutID = item.playerOutID
                existing.minute = item.minute
            } else {
                context.insert(Substitution(
                    id: item.id,
                    matchID: item.matchID,
                    playerInID: item.playerInID,
                    playerOutID: item.playerOutID,
                    minute: item.minute
                ))
            }
            summary.substitutions += 1
        }

        try context.save()

        // 試合時間設定は「今の端末の内容+バックアップの内容」を合体(バックアップ優先)
        if let merged = mergedClockSettingsRaw(
            current: UserDefaults.standard.data(forKey: clockSettingsKey),
            backup: backup.matchClockSettingsRaw
        ) {
            UserDefaults.standard.set(merged, forKey: clockSettingsKey)
        }

        // デフォルト自チーム名は、端末側が未設定のときだけ持ち込む
        if let name = backup.defaultTeamName, !name.isEmpty,
           (UserDefaults.standard.string(forKey: defaultTeamNameKey) ?? "").isEmpty {
            UserDefaults.standard.set(name, forKey: defaultTeamNameKey)
        }

        return summary
    }

    // MARK: - 画像の変換

    private static func imageBase64(named name: String?) -> String? {
        guard let name else { return nil }
        let url = URL.documentsDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }

    private static func savedImageName(fromBase64 base64: String?) -> String? {
        guard let base64, let data = Data(base64Encoded: base64) else { return nil }
        return ImageStorage.save(data)
    }

    // 試合時間設定(試合IDごとの辞書)を、中身の型を知らずに合体させる
    private static func mergedClockSettingsRaw(current: Data?, backup: Data?) -> Data? {
        guard let backup else { return current }
        guard let current else { return backup }
        guard let currentDict = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any],
              let backupDict = (try? JSONSerialization.jsonObject(with: backup)) as? [String: Any] else {
            return backup
        }
        let merged = currentDict.merging(backupDict) { _, backupValue in backupValue }
        return try? JSONSerialization.data(withJSONObject: merged)
    }
}

// MARK: - 共有シートに渡す「バックアップファイルのもと」
// 共有される瞬間に全データを集めてファイル化する(タップまでは何もしない)

struct BackupExportRequest: Transferable {
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { request in
            let context = ModelContext(request.container)
            let data = try BackupManager.makeBackupData(context: context)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd"
            let fileName = "RugbyAS_backup_\(formatter.string(from: Date())).json"

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url)
            return SentTransferredFile(url)
        }
    }
}
