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
