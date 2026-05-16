//
//  ContentView.swift
//  Rugby AS
//
//  Created by 35 on 2026/05/17.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \Match.playedAt, order: .reverse) private var matches: [Match]
    @Query private var teams: [Team]
    @Query private var tournaments: [Tournament]
    @State private var isShowingCreateMatch = false

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
                        MatchRow(
                            match: match,
                            tournamentName: tournamentName(for: match),
                            homeTeamName: teamName(for: match.homeTeamID),
                            awayTeamName: teamName(for: match.awayTeamID)
                        )
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
        }
    }

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム未設定"
    }

    private func tournamentName(for match: Match) -> String {
        tournaments.first { $0.id == match.tournamentID }?.officialName ?? "大会未設定"
    }
}

private struct MatchRow: View {
    let match: Match
    let tournamentName: String
    let homeTeamName: String
    let awayTeamName: String

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

            Text("記録中")
                .font(.caption)
                .foregroundStyle(.blue)
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
