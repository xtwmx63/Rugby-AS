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
    private static let headerLine =
        "大会,試合日,ホーム,アウェイ,前後半,時間,カテゴリ,カテゴリID,チーム,背番号,選手名,結果,継続秒,起点"

    static func makeFile(
        match: Match,
        events: [StatEvent],
        teams: [Team],
        players: [Player],
        lineups: [MatchLineup] = [],
        tournamentName: String
    ) -> MatchCSVFile {
        let homeName = teamName(for: match.homeTeamID, in: teams)
        let awayName = teamName(for: match.awayTeamID, in: teams)

        let lines = [headerLine] + rowLines(
            match: match,
            events: events,
            teams: teams,
            players: players,
            lineups: lineups,
            tournamentName: tournamentName
        )

        let safeName = sanitizedFileName(
            "\(homeName)_vs_\(awayName)_\(fileDateFormatter.string(from: match.playedAt)).csv"
        )

        return MatchCSVFile(fileName: safeName, csvText: lines.joined(separator: "\n") + "\n")
    }

    /// 大会の全試合を1つのCSVにまとめる(試合日の古い順)
    static func makeTournamentFile(
        tournamentName: String,
        matches: [Match],
        events: [StatEvent],
        teams: [Team],
        players: [Player],
        lineups: [MatchLineup] = []
    ) -> MatchCSVFile {
        var lines = [headerLine]

        let sortedMatches = matches.sorted { $0.playedAt < $1.playedAt }
        for match in sortedMatches {
            let matchEvents = events.filter { $0.matchID == match.id }
            lines += rowLines(
                match: match,
                events: matchEvents,
                teams: teams,
                players: players,
                lineups: lineups,
                tournamentName: tournamentName
            )
        }

        let safeName = sanitizedFileName(
            "\(tournamentName)_全試合_\(fileDateFormatter.string(from: Date())).csv"
        )

        return MatchCSVFile(fileName: safeName, csvText: lines.joined(separator: "\n") + "\n")
    }

    // 1試合分の行(ヘッダーなし)。単体書き出しと大会一括の両方から使う
    private static func rowLines(
        match: Match,
        events: [StatEvent],
        teams: [Team],
        players: [Player],
        lineups: [MatchLineup],
        tournamentName: String
    ) -> [String] {
        let homeName = teamName(for: match.homeTeamID, in: teams)
        let awayName = teamName(for: match.awayTeamID, in: teams)
        let dateText = dateFormatter.string(from: match.playedAt)

        let rows = events
            .filter { $0.category != "match_state" }
            .sorted { sortKey($0) < sortKey($1) }

        return rows.map { event in
            let player = players.first { $0.id == event.playerID }
            // 背番号はその試合のメンバー表の番号(なければ基本番号。背番号なしは空欄)
            let number = player.flatMap {
                MatchNumbering.number(for: $0, matchID: match.id, lineups: lineups)
            }
            return [
                tournamentName,
                dateText,
                homeName,
                awayName,
                event.half >= 1 ? "後半" : "前半",
                timeText(displaySeconds(for: event)),
                categoryLabel(event.category),
                event.category,
                teamLabel(for: event, homeName: homeName, awayName: awayName, teams: teams),
                number.map(String.init) ?? "",
                player?.name ?? "",
                outcomeLabel(event.outcome),
                event.category == "possession" ? String(event.seconds) : "",
                PlayOrigin.displayName(for: event.origin) ?? ""
            ]
            .map(escaped)
            .joined(separator: ",")
        }
    }

    private static func sanitizedFileName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
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
        case "penalty": return "ペナルティ(反則)"
        default: return category
        }
    }

    private static func outcomeLabel(_ outcome: String) -> String {
        switch outcome {
        case "success": return "成功"
        case "fail": return "失敗"
        case "own": return "自チーム保持"
        case "opponent": return "相手保持"
        case "conceded": return "反則"
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
