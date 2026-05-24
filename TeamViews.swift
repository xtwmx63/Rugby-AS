//
//  TeamViews.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import PhotosUI
import SwiftData
import SwiftUI

struct TeamListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var teamPendingDeletion: Team?
    @State private var deletionBlockedTeam: Team?

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
                        HStack(spacing: 12) {
                            teamListThumbnail(for: team)
                            Text(team.name)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("削除", role: .destructive) {
                            requestDeletion(of: team)
                        }
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
        .confirmationDialog(
            "このチームを削除しますか？",
            isPresented: Binding(
                get: { teamPendingDeletion != nil },
                set: { if !$0 { teamPendingDeletion = nil } }
            ),
            presenting: teamPendingDeletion,
            actions: { team in
                Button("削除する", role: .destructive) {
                    deleteTeam(team)
                    teamPendingDeletion = nil
                }
                Button("キャンセル", role: .cancel) {
                    teamPendingDeletion = nil
                }
            },
            message: { team in
                Text("チーム「\(team.name)」と、所属する選手・写真をまとめて削除します。")
            }
        )
        .alert(
            "削除できません",
            isPresented: Binding(
                get: { deletionBlockedTeam != nil },
                set: { if !$0 { deletionBlockedTeam = nil } }
            ),
            presenting: deletionBlockedTeam,
            actions: { _ in
                Button("OK", role: .cancel) {
                    deletionBlockedTeam = nil
                }
            },
            message: { team in
                Text("「\(team.name)」は試合で使われているため削除できません。先に該当する試合を削除してください。")
            }
        )
    }

    private func requestDeletion(of team: Team) {
        if isTeamUsedInAnyMatch(team) {
            deletionBlockedTeam = team
        } else {
            teamPendingDeletion = team
        }
    }

    private func isTeamUsedInAnyMatch(_ team: Team) -> Bool {
        let teamID = team.id
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { match in
                match.homeTeamID == teamID || match.awayTeamID == teamID
            }
        )
        return ((try? modelContext.fetch(descriptor).first) != nil)
    }

    private func deleteTeam(_ team: Team) {
        // ロゴ画像を消す（端末内ファイル）
        if let logoName = team.logoPath {
            ImageStorage.delete(named: logoName)
        }
        // 所属選手と各選手の写真を消す
        let teamID = team.id
        let playerDescriptor = FetchDescriptor<Player>(
            predicate: #Predicate { player in player.teamID == teamID }
        )
        if let players = try? modelContext.fetch(playerDescriptor) {
            for player in players {
                if let photoName = player.imagePath {
                    ImageStorage.delete(named: photoName)
                }
                modelContext.delete(player)
            }
        }
        modelContext.delete(team)
        try? modelContext.save()
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

    @ViewBuilder
    private func teamListThumbnail(for team: Team) -> some View {
        if let name = team.logoPath, let uiImage = ImageStorage.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
        }
    }
}

struct TeamEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var team: Team
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var isShowingLogoDeleteConfirmation = false

    private var players: [Player] {
        allPlayers
            .filter { $0.teamID == team.id }
            .sorted { $0.number < $1.number }
    }

    var body: some View {
        Form {
            Section("チーム") {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $logoPickerItem, matching: .images) {
                        logoThumbnail
                    }
                    .buttonStyle(.plain)

                    TextField("チーム名", text: $team.name)
                }

                if team.logoPath != nil {
                    Button("ロゴを削除", role: .destructive) {
                        isShowingLogoDeleteConfirmation = true
                    }
                }
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
        .onChange(of: logoPickerItem) { newItem in
            handleSelectedLogo(newItem)
        }
        .confirmationDialog(
            "ロゴを削除しますか？",
            isPresented: $isShowingLogoDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                deleteLogo()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }

    @ViewBuilder
    private var logoThumbnail: some View {
        if let name = team.logoPath, let uiImage = ImageStorage.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.secondary)
        }
    }

    private func handleSelectedLogo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                if let data, let newName = ImageStorage.save(data) {
                    if let oldName = team.logoPath {
                        ImageStorage.delete(named: oldName)
                    }
                    team.logoPath = newName
                    try? modelContext.save()
                }
                logoPickerItem = nil
            }
        }
    }

    private func deleteLogo() {
        if let name = team.logoPath {
            ImageStorage.delete(named: name)
        }
        team.logoPath = nil
        try? modelContext.save()
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
    @Environment(\.modelContext) private var modelContext
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isShowingPhotoDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                photoThumbnail
            }
            .buttonStyle(.plain)

            Text("#\(player.number)")
                .font(.headline.monospacedDigit())
                .frame(width: 36, alignment: .leading)

            TextField("名前（任意）", text: playerName)
                .textInputAutocapitalization(.words)

            if player.imagePath != nil {
                Button {
                    isShowingPhotoDeleteConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: photoPickerItem) { newItem in
            handleSelectedPhoto(newItem)
        }
        .confirmationDialog(
            "写真を削除しますか？",
            isPresented: $isShowingPhotoDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                deletePhoto()
            }
            Button("キャンセル", role: .cancel) { }
        }
    }

    @ViewBuilder
    private var photoThumbnail: some View {
        if let name = player.imagePath, let uiImage = ImageStorage.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
        }
    }

    private func handleSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                if let data, let newName = ImageStorage.save(data) {
                    if let oldName = player.imagePath {
                        ImageStorage.delete(named: oldName)
                    }
                    player.imagePath = newName
                    try? modelContext.save()
                }
                photoPickerItem = nil
            }
        }
    }

    private func deletePhoto() {
        if let name = player.imagePath {
            ImageStorage.delete(named: name)
        }
        player.imagePath = nil
        try? modelContext.save()
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
