//
//  ContentView.swift
//  Rugby AS
//
//  Created by 35 on 2026/05/17.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Match.playedAt, order: .reverse) private var matches: [Match]
    @Query private var teams: [Team]
    @Query private var tournaments: [Tournament]
    @Query private var events: [StatEvent]
    @State private var isShowingCreateMatch = false
    @State private var matchPendingDeletion: Match?

    var body: some View {
        NavigationStack {
            Group {
                if matches.isEmpty {
                    ContentUnavailableView(
                        "試合がありません",
                        systemImage: "sportscourt",
                        description: Text("右上の＋から試合を追加します。")
                    )
                } else {
                    List(matches) { match in
                        NavigationLink {
                            if isFinished(match) {
                                MatchSummaryView(match: match)
                            } else {
                                // 記録前にスタメン/リザーブの確認・編集を挟む。
                                // 「保存」で V3RecordingView に進む。
                                LineupRegistrationView(match: match)
                            }
                        } label: {
                            MatchRow(
                                match: match,
                                tournamentName: tournamentName(for: match),
                                homeTeamName: teamName(for: match.homeTeamID),
                                awayTeamName: teamName(for: match.awayTeamID),
                                isFinished: isFinished(match)
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("削除", role: .destructive) {
                                matchPendingDeletion = match
                            }
                        }
                    }
                }
            }
            .navigationTitle("試合一覧")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        TeamListView()
                    } label: {
                        Label("チーム", systemImage: "person.3")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingCreateMatch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("試合を追加")
                }
            }
            .sheet(isPresented: $isShowingCreateMatch) {
                NavigationStack {
                    CreateMatchView()
                }
            }
            .alert(
                "この試合を削除しますか？",
                isPresented: Binding(
                    get: { matchPendingDeletion != nil },
                    set: { if !$0 { matchPendingDeletion = nil } }
                ),
                presenting: matchPendingDeletion
            ) { match in
                Button("削除する", role: .destructive) {
                    deleteMatch(match)
                }
                Button("キャンセル", role: .cancel) { }
            } message: { match in
                Text(deletionMessage(for: match))
            }
        }
    }

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
    }

    private func tournamentName(for match: Match) -> String {
        tournaments.first { $0.id == match.tournamentID }?.officialName ?? "大会未設定"
    }

    private func isFinished(_ match: Match) -> Bool {
        events.contains { event in
            event.matchID == match.id && event.category == "match_state" && event.outcome == "finished"
        }
    }

    private func deletionMessage(for match: Match) -> String {
        let date = match.playedAt.formatted(date: .numeric, time: .omitted)
        return "\(teamName(for: match.homeTeamID)) vs \(teamName(for: match.awayTeamID))\n\(date)\n\n記録したスタッツもすべて削除され、元に戻せません。"
    }

    private func deleteMatch(_ match: Match) {
        // SwiftData の @Relationship は未定義のため、StatEvent は自動カスケード削除されない。
        // 孤児を残さないよう、紐づく StatEvent を明示的に全削除してから Match を削除する。
        let relatedEvents = events.filter { $0.matchID == match.id }
        for event in relatedEvents {
            modelContext.delete(event)
        }
        modelContext.delete(match)
        try? modelContext.save()
    }
}

private struct MatchRow: View {
    let match: Match
    let tournamentName: String
    let homeTeamName: String
    let awayTeamName: String
    let isFinished: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(homeTeamName) vs \(awayTeamName)")
                .font(.headline)

            HStack {
                Text(tournamentName)
                Spacer()
                Text(match.playedAt, style: .date)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text(isFinished ? "終了" : "記録中")
                .font(.caption)
                .foregroundStyle(isFinished ? Color.secondary : Color.blue)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            Team.self,
            Player.self,
            Tournament.self,
            Match.self,
            StatEvent.self,
            Substitution.self
        ], inMemory: true)
}
