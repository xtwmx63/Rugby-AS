//
//  TeamViews.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import SwiftData
import SwiftUI

struct TeamListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var teams: [Team]

    var body: some View {
        List {
            if teams.isEmpty {
                ContentUnavailableView(
                    "チームがありません",
                    systemImage: "person.3",
                    description: Text("右上の＋からチームを追加します。")
                )
            } else {
                ForEach(teams) { team in
                    NavigationLink {
                        TeamEditorView(team: team)
                    } label: {
                        Text(team.name)
                    }
                }
            }
        }
        .navigationTitle("チーム")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addTeam()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("チームを追加")
            }
        }
    }

    private func addTeam() {
        let team = Team(name: "新しいチーム")
        modelContext.insert(team)
        addInitialPlayers(for: team)
    }

    private func addInitialPlayers(for team: Team) {
        for number in 1...15 {
            let player = Player(teamID: team.id, number: number)
            modelContext.insert(player)
        }
    }
}

struct TeamEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var team: Team
    @Query(sort: \Player.number) private var allPlayers: [Player]

    private var players: [Player] {
        allPlayers
            .filter { $0.teamID == team.id }
            .sorted { $0.number < $1.number }
    }

    var body: some View {
        Form {
            Section("チーム") {
                TextField("チーム名", text: $team.name)
            }

            Section {
                ForEach(players) { player in
                    PlayerRow(player: player)
                }

                Button {
                    addPlayerSlot()
                } label: {
                    Label("追加", systemImage: "plus")
                }
            } header: {
                Text("メンバー表")
            } footer: {
                Text("名前は空欄のままでも記録できます。選手の完全削除はV1では扱いません。")
            }
        }
        .navigationTitle(team.name.isEmpty ? "チーム編集" : team.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureInitialPlayers()
        }
    }

    private func ensureInitialPlayers() {
        let existingNumbers = Set(players.map(\.number))
        for number in 1...15 where !existingNumbers.contains(number) {
            let player = Player(teamID: team.id, number: number)
            modelContext.insert(player)
        }
    }

    private func addPlayerSlot() {
        let nextNumber = (players.map(\.number).max() ?? 0) + 1
        let player = Player(teamID: team.id, number: nextNumber)
        modelContext.insert(player)
    }
}

private struct PlayerRow: View {
    @Bindable var player: Player

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(player.number)")
                .font(.headline.monospacedDigit())
                .frame(width: 44, alignment: .leading)

            TextField("名前（任意）", text: playerName)
                .textInputAutocapitalization(.words)
        }
    }

    private var playerName: Binding<String> {
        Binding(
            get: { player.name ?? "" },
            set: { newValue in
                let trimmedName = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                player.name = trimmedName.isEmpty ? nil : trimmedName
            }
        )
    }
}

#Preview {
    NavigationStack {
        TeamListView()
    }
    .modelContainer(for: [
        Team.self,
        Player.self,
        Tournament.self,
        Match.self,
        StatEvent.self,
        Substitution.self
    ], inMemory: true)
}
