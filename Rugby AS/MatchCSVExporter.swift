//
//  MatchCSVExporter.swift
//  Rugby AS
//
//  試合の記録(StatEvent)をCSVファイルにして共有するための部品。
//  1行=1記録の表形式。ExcelやNumbersでそのまま開けるよう
//  UTF-8 BOM付きで書き出す(BOMがないとExcelで日本語が化ける)。
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// 共有シート(ShareLink)に渡す「CSVファイルのもと」。
// 実際のファイルは共有される瞬間に一時フォルダへ書き出される。
struct MatchCSVFile: Transferable {
    let fileName: String
    let csvText: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(file.fileName)
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(file.csvText.utf8))
            try data.write(to: url)
            return SentTransferredFile(url)
        }
    }
}

enum MatchCSVExporter {
    static func makeFile(
        match: Match,
        events: [StatEvent],
        teams: [Team],
        players: [Player],
        tournamentName: String
    ) -> MatchCSVFile {
        let homeName = teamName(for: match.homeTeamID, in: teams)
        let awayName = teamName(for: match.awayTeamID, in: teams)
        let dateText = dateFormatter.string(from: match.playedAt)

        var lines: [String] = [
            "大会,試合日,ホーム,アウェイ,前後半,時間,カテゴリ,カテゴリID,チーム,背番号,選手名,結果,継続秒"
        ]

        let rows = events
            .filter { $0.category != "match_state" }
            .sorted { sortKey($0) < sortKey($1) }

        for event in rows {
            let player = players.first { $0.id == event.playerID }
            let line = [
                tournamentName,
                dateText,
                homeName,
                awayName,
                event.half >= 1 ? "後半" : "前半",
                timeText(displaySeconds(for: event)),
                categoryLabel(event.category),
                event.category,
                teamLabel(for: event, homeName: homeName, awayName: awayName, teams: teams),
                player.map { String($0.number) } ?? "",
                player?.name ?? "",
                outcomeLabel(event.outcome),
                event.category == "possession" ? String(event.seconds) : ""
            ]
            .map(escaped)
            .joined(separator: ",")

            lines.append(line)
        }

        let safeName = "\(homeName)_vs_\(awayName)_\(fileDateFormatter.string(from: match.playedAt)).csv"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        return MatchCSVFile(fileName: safeName, csvText: lines.joined(separator: "\n") + "\n")
    }

    // ポゼッションは seconds が「継続秒数」なので、開始時刻の方を表示に使う
    private static func displaySeconds(for event: StatEvent) -> Int {
        if event.category == "possession" {
            return event.startSeconds ?? 0
        }
        return event.seconds
    }

    private static func sortKey(_ event: StatEvent) -> (Int, Int) {
        (event.half, displaySeconds(for: event))
    }

    private static func teamName(for id: UUID, in teams: [Team]) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
    }

    private static func teamLabel(
        for event: StatEvent,
        homeName: String,
        awayName: String,
        teams: [Team]
    ) -> String {
        if let teamID = event.teamID {
            return teams.first { $0.id == teamID }?.name ?? ""
        }
        // ポゼッションで own/opponent だけ記録された古いデータへの対応
        if event.outcome == "own" { return homeName }
        if event.outcome == "opponent" { return awayName }
        return ""
    }

    private static func categoryLabel(_ category: String) -> String {
        switch category {
        case "possession": return "ポゼッション"
        case "try": return "トライ"
        case "conversion": return "コンバージョン"
        case "penalty_goal": return "ペナルティゴール"
        case "drop_goal": return "ドロップゴール"
        case "lineout": return "ラインアウト"
        case "scrum": return "スクラム"
        default: return category
        }
    }

    private static func outcomeLabel(_ outcome: String) -> String {
        switch outcome {
        case "success": return "成功"
        case "fail": return "失敗"
        case "own": return "自チーム保持"
        case "opponent": return "相手保持"
        case "none": return ""
        default: return outcome
        }
    }

    private static func timeText(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // カンマや改行を含む値はダブルクォートで包む(CSVの決まりごと)
    private static func escaped(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
