//
//  TournamentCSVExportSheet.swift
//  Rugby AS
//
//  大会を選ぶと、その大会の全試合の記録を1つのCSVにまとめて共有できる。
//  CSVの列は1試合用と同じ(大会・試合日・チーム名が全行に入る形)なので、
//  Excelでそのまま大会全体の集計ができる。
//

import CoreTransferable
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// 共有シートに渡す「大会CSVのもと」。共有される瞬間にデータを集めてファイル化する
struct TournamentCSVExportRequest: Transferable {
    let container: ModelContainer
    let tournamentID: UUID
    let tournamentName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { request in
            let context = ModelContext(request.container)
            let tournamentID = request.tournamentID

            let matches = try context.fetch(
                FetchDescriptor<Match>(
                    predicate: #Predicate<Match> { $0.tournamentID == tournamentID }
                )
            )
            let matchIDs = Set(matches.map(\.id))
            let events = try context.fetch(FetchDescriptor<StatEvent>())
                .filter { matchIDs.contains($0.matchID) }
            let teams = try context.fetch(FetchDescriptor<Team>())
            let players = try context.fetch(FetchDescriptor<Player>())

            let file = MatchCSVExporter.makeTournamentFile(
                tournamentName: request.tournamentName,
                matches: matches,
                events: events,
                teams: teams,
                players: players
            )

            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(file.csvText.utf8))
            try data.write(to: url)
            return SentTransferredFile(url)
        }
    }
}

struct TournamentCSVExportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tournament.officialName) private var tournaments: [Tournament]
    @Query private var matches: [Match]

    var body: some View {
        NavigationStack {
            List {
                if tournaments.isEmpty {
                    Text("大会がまだありません")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(tournaments) { tournament in
                            tournamentRow(tournament)
                        }
                    } footer: {
                        Text("大会を選ぶと、その大会の全試合の記録を1つのCSVファイルにまとめて共有します。")
                    }
                }
            }
            .navigationTitle("大会ごとのCSV書き出し")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func tournamentRow(_ tournament: Tournament) -> some View {
        let matchCount = matches.count { $0.tournamentID == tournament.id }

        return ShareLink(
            item: TournamentCSVExportRequest(
                container: modelContext.container,
                tournamentID: tournament.id,
                tournamentName: tournament.officialName
            ),
            preview: SharePreview("\(tournament.officialName) 全試合CSV")
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tournament.officialName)
                        .foregroundStyle(matchCount == 0 ? Color.secondary : Color.primary)
                    Text("\(matchCount)試合")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(matchCount == 0)
    }
}

#Preview {
    TournamentCSVExportSheet()
        .modelContainer(for: [
            Team.self,
            Player.self,
            Tournament.self,
            Match.self,
            StatEvent.self,
            MatchLineup.self,
            Substitution.self
        ], inMemory: true)
}
