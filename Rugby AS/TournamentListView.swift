//
//  TournamentListView.swift
//  Rugby AS
//
//  大会の一覧。チーム一覧と同じ流儀で、追加(右上の＋)と
//  スワイプ削除ができる。試合が登録されている大会は削除できない
//  (先に試合を消してもらう。記録を巻き添えにしないため)。
//  各行の共有ボタンから、その大会の全試合CSVも書き出せる。
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

struct TournamentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tournament.officialName) private var tournaments: [Tournament]
    @Query private var matches: [Match]

    @State private var isAddAlertPresented = false
    @State private var newTournamentName = ""
    @State private var tournamentPendingDeletion: Tournament?
    @State private var deletionBlockedTournament: Tournament?

    var body: some View {
        NavigationStack {
            List {
                if tournaments.isEmpty {
                    ContentUnavailableView(
                        "大会がありません",
                        systemImage: "trophy",
                        description: Text("右上の＋から大会を追加します。")
                    )
                } else {
                    Section {
                        ForEach(tournaments) { tournament in
                            tournamentRow(tournament)
                        }
                    } footer: {
                        Text("共有ボタンで、その大会の全試合の記録を1つのCSVにまとめて書き出せます。")
                    }
                }
            }
            .navigationTitle("大会")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newTournamentName = ""
                        isAddAlertPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("大会を追加")
                }
            }
            .alert("大会を追加", isPresented: $isAddAlertPresented) {
                TextField("大会の正式名称", text: $newTournamentName)
                Button("追加") {
                    addTournament()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("大会の正式名称を入力してください。")
            }
            .confirmationDialog(
                "この大会を削除しますか？",
                isPresented: Binding(
                    get: { tournamentPendingDeletion != nil },
                    set: { if !$0 { tournamentPendingDeletion = nil } }
                ),
                presenting: tournamentPendingDeletion,
                actions: { tournament in
                    Button("削除する", role: .destructive) {
                        delete(tournament)
                        tournamentPendingDeletion = nil
                    }
                    Button("キャンセル", role: .cancel) {
                        tournamentPendingDeletion = nil
                    }
                },
                message: { tournament in
                    Text("大会「\(tournament.officialName)」を削除します。")
                }
            )
            .alert(
                "削除できません",
                isPresented: Binding(
                    get: { deletionBlockedTournament != nil },
                    set: { if !$0 { deletionBlockedTournament = nil } }
                ),
                presenting: deletionBlockedTournament,
                actions: { _ in
                    Button("OK", role: .cancel) {
                        deletionBlockedTournament = nil
                    }
                },
                message: { tournament in
                    Text("「\(tournament.officialName)」には試合が登録されているため削除できません。先に該当する試合を削除してください。")
                }
            )
        }
    }

    private func tournamentRow(_ tournament: Tournament) -> some View {
        let matchCount = matches.count { $0.tournamentID == tournament.id }

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tournament.officialName)
                Text("\(matchCount)試合")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ShareLink(
                item: TournamentCSVExportRequest(
                    container: modelContext.container,
                    tournamentID: tournament.id,
                    tournamentName: tournament.officialName
                ),
                preview: SharePreview("\(tournament.officialName) 全試合CSV")
            ) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(matchCount == 0 ? Color.secondary.opacity(0.4) : Color.accentColor)
            }
            .disabled(matchCount == 0)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("削除", role: .destructive) {
                requestDeletion(of: tournament)
            }
        }
    }

    private func addTournament() {
        let name = newTournamentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(Tournament(officialName: name))
        try? modelContext.save()
    }

    private func requestDeletion(of tournament: Tournament) {
        let tournamentID = tournament.id
        if matches.contains(where: { $0.tournamentID == tournamentID }) {
            deletionBlockedTournament = tournament
        } else {
            tournamentPendingDeletion = tournament
        }
    }

    private func delete(_ tournament: Tournament) {
        modelContext.delete(tournament)
        try? modelContext.save()
    }
}

#Preview {
    TournamentListView()
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
