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
            let lineups = try context.fetch(FetchDescriptor<MatchLineup>())
                .filter { matchIDs.contains($0.matchID) }

            let file = MatchCSVExporter.makeTournamentFile(
                tournamentName: request.tournamentName,
                matches: matches,
                events: events,
                teams: teams,
                players: players,
                lineups: lineups
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

    @State private var editingTournament: Tournament?
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
                    // 同じ名前の大会を1つのフォルダにまとめ、年度の新しい順に並べる。
                    // これで「〇〇大会」の各年度（過去の年度）が一箇所に集まる。
                    ForEach(groupedTournaments, id: \.name) { group in
                        Section {
                            ForEach(group.editions) { tournament in
                                tournamentRow(tournament)
                            }
                        } header: {
                            Text(group.name)
                        }
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
                        addTournament()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("大会を追加")
                }
            }
            .sheet(item: $editingTournament) { tournament in
                TournamentEditorView(tournament: tournament)
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

    // 同名の大会をまとめ、フォルダ（＝大会名）ごとに年度の新しい順で並べる
    private var groupedTournaments: [(name: String, editions: [Tournament])] {
        let grouped = Dictionary(grouping: tournaments) { $0.officialName }
        return grouped.keys.sorted().map { name in
            let editions = (grouped[name] ?? []).sorted {
                ($0.year ?? Int.min) > ($1.year ?? Int.min)
            }
            return (name: name, editions: editions)
        }
    }

    private func tournamentRow(_ tournament: Tournament) -> some View {
        let matchCount = matches.count { $0.tournamentID == tournament.id }

        return NavigationLink {
            TournamentDetailView(tournament: tournament)
        } label: {
            HStack(spacing: 10) {
                logoThumbnail(for: tournament)

                VStack(alignment: .leading, spacing: 2) {
                    // 同名でも年度で区別できるよう、年度があれば見出しに出す
                    Text(tournament.year.map { "\(String($0))年度" } ?? tournament.officialName)
                        .font(.headline)
                    HStack(spacing: 6) {
                        if let variant = RugbyVariant.displayName(for: tournament.variantRaw) {
                            Text(variant)
                        }
                        Text("\(tournament.teamIDs.count)チーム・\(matchCount)試合")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    editingTournament = tournament
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("削除", role: .destructive) {
                requestDeletion(of: tournament)
            }
            Button("編集") {
                editingTournament = tournament
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func logoThumbnail(for tournament: Tournament) -> some View {
        if let name = tournament.logoPath, let uiImage = ImageStorage.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
                .frame(width: 34, height: 34)
        }
    }

    private func addTournament() {
        let tournament = Tournament(officialName: "新しい大会")
        modelContext.insert(tournament)
        try? modelContext.save()
        editingTournament = tournament
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
