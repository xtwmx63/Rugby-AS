//
//  LineupRegistrationView.swift
//  Rugby AS
//
//  試合記録の前に、その試合のスタメンとリザーブを登録する画面。
//

import SwiftData
import SwiftUI

struct LineupRegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var teams: [Team]
    // この試合の 2 チームの選手だけに絞る。全選手をフェッチして main thread で
    // ソート → 毎フレーム body 内で再 filter するのは重い。
    @Query private var allPlayers: [Player]
    @Query private var lineupEntries: [MatchLineup]

    let match: Match

    @State private var selectedTeamID: UUID?
    @State private var addingContext: AddingContext?
    @State private var pendingRemoval: MatchLineup?
    @State private var navigatesToRecording = false

    init(match: Match) {
        self.match = match
        let matchID = match.id
        let homeID = match.homeTeamID
        let awayID = match.awayTeamID
        _lineupEntries = Query(filter: #Predicate<MatchLineup> { entry in
            entry.matchID == matchID
        })
        _allPlayers = Query(
            filter: #Predicate<Player> { player in
                player.teamID == homeID || player.teamID == awayID
            },
            sort: [SortDescriptor(\Player.number)]
        )
    }

    private var currentTeamID: UUID {
        selectedTeamID ?? match.homeTeamID
    }

    private var teamLineupEntries: [MatchLineup] {
        lineupEntries.filter { $0.teamID == currentTeamID }
    }

    private var starters: [MatchLineup] {
        teamLineupEntries.filter { $0.role == "starter" }.sorted { $0.order < $1.order }
    }

    private var reserves: [MatchLineup] {
        teamLineupEntries.filter { $0.role == "reserve" }.sorted { $0.order < $1.order }
    }

    private var teamPlayers: [Player] {
        allPlayers.filter { $0.teamID == currentTeamID }
    }

    private var availablePlayers: [Player] {
        let registered = Set(teamLineupEntries.map { $0.playerID })
        return teamPlayers.filter { !registered.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                teamHeader
                teamToggle
                sectionView(title: "スタメン", entries: starters, role: "starter")
                sectionView(title: "リザーブ", entries: reserves, role: "reserve")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .navigationTitle("メンバー登録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    navigatesToRecording = true
                }
                .bold()
            }
        }
        // 同じ NavigationStack に navigationDestination(item:) と
        // navigationDestination(isPresented:) を入れ子で重ねると、後者が
        // 無視されることがある SwiftUI の挙動を避けるため、ここは fullScreenCover で出す。
        .fullScreenCover(isPresented: $navigatesToRecording) {
            V3RecordingView(match: match)
        }
        .sheet(item: $addingContext) { context in
            playerPickerSheet(role: context.role)
        }
        .confirmationDialog(
            "この選手を外しますか？",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { entry in
            Button("外す", role: .destructive) {
                modelContext.delete(entry)
                try? modelContext.save()
                pendingRemoval = nil
            }
            Button("キャンセル", role: .cancel) {
                pendingRemoval = nil
            }
        }
    }

    // MARK: - Header

    private var teamHeader: some View {
        HStack(spacing: 12) {
            teamLogo(for: match.homeTeamID)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(teamName(for: match.homeTeamID))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("HOME")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.blue)
            }
            Spacer(minLength: 4)
            VStack(spacing: 2) {
                Text("VS")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.secondary)
                Text("試合前登録")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(teamName(for: match.awayTeamID))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("AWAY")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.red)
            }
            teamLogo(for: match.awayTeamID)
                .frame(width: 44, height: 44)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func teamLogo(for teamID: UUID) -> some View {
        let team = teams.first { $0.id == teamID }
        Group {
            if let team, let logoName = team.logoPath, let uiImage = ImageStorage.image(named: logoName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Toggle

    private var teamToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("登録対象")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("登録対象", selection: Binding(
                get: { currentTeamID },
                set: { selectedTeamID = $0 }
            )) {
                Text("HOME").tag(match.homeTeamID)
                Text("AWAY").tag(match.awayTeamID)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Section

    private func sectionView(title: String, entries: [MatchLineup], role: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text("\(entries.count)人")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 80), spacing: 12)
            ], spacing: 12) {
                ForEach(entries) { entry in
                    if let player = player(for: entry) {
                        playerCard(player: player) {
                            pendingRemoval = entry
                        }
                    }
                }
                addCard(role: role)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func playerCard(player: Player, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                playerAvatar(player: player)
                    .frame(width: 56, height: 56)
                Text("#\(player.number)")
                    .font(.caption.monospacedDigit().weight(.bold))
                Text(player.name ?? "名前未設定")
                    .font(.caption2)
                    .foregroundStyle(player.name == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 72)
            }
            .padding(8)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func playerAvatar(player: Player) -> some View {
        if let imagePath = player.imagePath, let uiImage = ImageStorage.image(named: imagePath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(.systemBackground))
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                )
        }
    }

    private func addCard(role: String) -> some View {
        let disabled = availablePlayers.isEmpty
        return Button {
            addingContext = AddingContext(role: role)
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    )
                Text("追加")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text(" ")
                    .font(.caption2)
                    .frame(width: 72)
            }
            .padding(8)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    // MARK: - Picker sheet

    private func playerPickerSheet(role: String) -> some View {
        NavigationStack {
            List {
                if availablePlayers.isEmpty {
                    ContentUnavailableView(
                        "追加できる選手がいません",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("チーム編集画面で選手を追加してください。")
                    )
                } else {
                    ForEach(availablePlayers) { player in
                        Button {
                            addPlayer(player, role: role)
                            addingContext = nil
                        } label: {
                            HStack {
                                Text("#\(player.number)")
                                    .font(.headline.monospacedDigit())
                                    .frame(width: 48, alignment: .leading)
                                Text(player.name ?? "名前未設定")
                                    .foregroundStyle(player.name == nil ? .secondary : .primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(role == "starter" ? "スタメンを追加" : "リザーブを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        addingContext = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func teamName(for id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "未設定"
    }

    private func player(for entry: MatchLineup) -> Player? {
        allPlayers.first { $0.id == entry.playerID }
    }

    private func addPlayer(_ player: Player, role: String) {
        let existing = teamLineupEntries.filter { $0.role == role }
        let nextOrder = (existing.map { $0.order }.max() ?? -1) + 1
        let entry = MatchLineup(
            matchID: match.id,
            teamID: currentTeamID,
            playerID: player.id,
            role: role,
            order: nextOrder
        )
        modelContext.insert(entry)
        try? modelContext.save()
    }

    private struct AddingContext: Identifiable {
        let role: String
        var id: String { role }
    }
}

#Preview {
    NavigationStack {
        LineupRegistrationView(
            match: Match(
                tournamentID: UUID(),
                homeTeamID: UUID(),
                awayTeamID: UUID(),
                playedAt: Date()
            )
        )
    }
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
