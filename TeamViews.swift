//
//  TeamViews.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import CoreImage
import PhotosUI
import SwiftData
import SwiftUI
import Vision

// MARK: - Color hex helpers

extension Color {
    /// "#RRGGBB" 形式の文字列から Color を作る。フォーマット不正なら nil。
    init?(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }

    /// 現在の Color を "#RRGGBB" 形式の文字列に変換する。
    func toHexString() -> String? {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded())
        )
    }

    /// 別の色との RGB 距離（0〜sqrt(3)）。値が小さいほど近い。
    func rgbDistance(to other: Color) -> Double {
        let lhs = UIColor(self)
        let rhs = UIColor(other)
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var rr: CGFloat = 0, rg: CGFloat = 0, rb: CGFloat = 0, ra: CGFloat = 0
        guard lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la),
              rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra) else { return 0 }
        let dr = Double(lr - rr)
        let dg = Double(lg - rg)
        let db = Double(lb - rb)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// HSB の brightness（0〜1）。視覚的な明るさの近似に使う。
    var hsbBrightness: Double {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return 1 }
        return Double(b)
    }

    /// HSB の hue（0〜1、円環状）。
    var hsbHue: Double {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return 0 }
        return Double(h)
    }

    /// 円環上の色相距離（0〜0.5）。小さいほど同系色。
    func hueDistance(to other: Color) -> Double {
        let diff = abs(self.hsbHue - other.hsbHue)
        return min(diff, 1 - diff)
    }

    /// 色相・彩度はそのままに、brightness だけ差し替えた Color を返す。
    func withBrightness(_ newBrightness: Double) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(
            hue: Double(h),
            saturation: Double(s),
            brightness: max(0, min(1, newBrightness))
        )
    }
}

// MARK: - Team color palette

struct TeamColorOption: Identifiable, Hashable {
    let hex: String
    let name: String
    var id: String { hex }
    var color: Color { Color(hex: hex) ?? .gray }
}

enum TeamColorPalette {
    static let options: [TeamColorOption] = [
        .init(hex: "#B71C1C", name: "クリムゾン"),
        .init(hex: "#E53935", name: "レッド"),
        .init(hex: "#FF7043", name: "コーラル"),
        .init(hex: "#FF8A65", name: "サーモン"),
        .init(hex: "#EF6C00", name: "パンプキン"),
        .init(hex: "#FB8C00", name: "オレンジ"),
        .init(hex: "#FFB300", name: "アンバー"),
        .init(hex: "#FDD835", name: "イエロー"),
        .init(hex: "#827717", name: "オリーブ"),
        .init(hex: "#C0CA33", name: "ライム"),
        .init(hex: "#43A047", name: "グリーン"),
        .init(hex: "#1B5E20", name: "フォレスト"),
        .init(hex: "#4DB6AC", name: "ミント"),
        .init(hex: "#00897B", name: "ティール"),
        .init(hex: "#00ACC1", name: "シアン"),
        .init(hex: "#26C6DA", name: "アクア"),
        .init(hex: "#29B6F6", name: "スカイ"),
        .init(hex: "#1E88E5", name: "ブルー"),
        .init(hex: "#3949AB", name: "ネイビー"),
        .init(hex: "#5C6BC0", name: "インディゴ"),
        .init(hex: "#9575CD", name: "ラベンダー"),
        .init(hex: "#8E24AA", name: "パープル"),
        .init(hex: "#6A1B9A", name: "プラム"),
        .init(hex: "#BA1FAB", name: "マゼンタ"),
        .init(hex: "#D81B60", name: "ピンク"),
        .init(hex: "#EC407A", name: "ローズピンク"),
        .init(hex: "#6D4C41", name: "ブラウン"),
        .init(hex: "#A1887F", name: "キャメル"),
        .init(hex: "#546E7A", name: "スレート")
    ]

    static func nearestDistinct(
        from preferred: Color,
        against home: Color,
        minDistance: Double,
        minHueDistance: Double = 0.04
    ) -> Color {
        let rgbOK = home.rgbDistance(to: preferred) >= minDistance
        let hueOK = home.hueDistance(to: preferred) >= minHueDistance
        if rgbOK && hueOK { return preferred }

        var bestColor: Color?
        var bestSimilarity = Double.infinity
        for option in options {
            let candidate = option.color
            guard home.rgbDistance(to: candidate) >= minDistance else { continue }
            guard home.hueDistance(to: candidate) >= minHueDistance else { continue }
            let similarity = preferred.rgbDistance(to: candidate)
            if similarity < bestSimilarity {
                bestSimilarity = similarity
                bestColor = candidate
            }
        }
        if let bestColor { return bestColor }

        return options.max {
            home.rgbDistance(to: $0.color) < home.rgbDistance(to: $1.color)
        }?.color ?? preferred
    }
}

// MARK: - Team list

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
                            VStack(alignment: .leading, spacing: 3) {
                                Text(team.name)
                                    .font(.headline)
                                Text("選手名簿とチームデザイン")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
            presenting: teamPendingDeletion
        ) { team in
            Button("削除する", role: .destructive) {
                deleteTeam(team)
                teamPendingDeletion = nil
            }
            Button("キャンセル", role: .cancel) {
                teamPendingDeletion = nil
            }
        } message: { team in
            Text("チーム「\(team.name)」と、所属する選手・写真をまとめて削除します。")
        }
        .alert(
            "削除できません",
            isPresented: Binding(
                get: { deletionBlockedTeam != nil },
                set: { if !$0 { deletionBlockedTeam = nil } }
            ),
            presenting: deletionBlockedTeam
        ) { _ in
            Button("OK", role: .cancel) {
                deletionBlockedTeam = nil
            }
        } message: { team in
            Text("「\(team.name)」は試合で使われているため削除できません。先に該当する試合を削除してください。")
        }
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
        var descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { match in
                match.homeTeamID == teamID || match.awayTeamID == teamID
            }
        )
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor).first) != nil)
    }

    private func deleteTeam(_ team: Team) {
        if let logoName = team.logoPath {
            ImageStorage.delete(named: logoName)
        }

        let teamID = team.id
        let descriptor = FetchDescriptor<Player>(
            predicate: #Predicate { player in player.teamID == teamID }
        )
        if let players = try? modelContext.fetch(descriptor) {
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
        for number in 1...15 {
            modelContext.insert(Player(teamID: team.id, number: number))
        }
        try? modelContext.save()
    }

    @ViewBuilder
    private func teamListThumbnail(for team: Team) -> some View {
        if let name = team.logoPath, let uiImage = ImageStorage.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .padding(8)
                .frame(width: 44, height: 44)
                .foregroundStyle(teamAccent(for: team))
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func teamAccent(for team: Team) -> Color {
        guard let hex = team.colorHex, let color = Color(hex: hex) else { return .blue }
        return color.hsbBrightness < 0.62 ? color.withBrightness(0.78) : color
    }
}

// MARK: - Team editor / collection roster

struct TeamEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var team: Team
    @Query(sort: \Player.number) private var allPlayers: [Player]

    @State private var logoPickerItem: PhotosPickerItem?
    @State private var isShowingLogoDeleteConfirmation = false
    @State private var isShowingColorPicker = false
    @State private var editingPlayer: Player?
    @State private var playerPendingDeletion: Player?
    @State private var deletionBlockedPlayer: Player?
    @State private var isShowingBulkKanaSheet = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var players: [Player] {
        allPlayers
            .filter { $0.teamID == team.id }
            .sorted {
                if ($0.number ?? Int.max) == ($1.number ?? Int.max) {
                    return ($0.name ?? "") < ($1.name ?? "")
                }
                return ($0.number ?? Int.max) < ($1.number ?? Int.max)
            }
    }

    private var registeredCount: Int {
        players.filter { player in
            player.imagePath != nil || !(player.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var duplicatedNumbers: Set<Int> {
        var seen: Set<Int> = []
        var duplicated: Set<Int> = []
        for player in players {
            guard let number = player.number else { continue }
            if !seen.insert(number).inserted { duplicated.insert(number) }
        }
        return duplicated
    }

    private var teamColor: Color {
        Color(hex: team.colorHex ?? "") ?? .blue
    }

    private var accent: Color {
        teamColor.hsbBrightness < 0.62 ? teamColor.withBrightness(0.80) : teamColor
    }

    private var selectedColorName: String {
        guard let hex = team.colorHex else { return "未設定" }
        return TeamColorPalette.options.first(where: { $0.hex == hex })?.name ?? hex
    }

    var body: some View {
        ZStack {
            rosterBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    teamIdentityCard
                    colorSelectionCard
                    rosterSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle(team.name.isEmpty ? "チーム編集" : team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.92), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { ensureInitialPlayers() }
        .onChange(of: logoPickerItem) { _, newItem in
            handleSelectedLogo(newItem)
        }
        .onChange(of: team.name) { _, _ in
            try? modelContext.save()
        }
        .sheet(isPresented: $isShowingColorPicker) {
            TeamColorPickerSheet(team: team)
        }
        .sheet(isPresented: $isShowingBulkKanaSheet) {
            BulkKanaInputSheet(players: players, accent: accent)
        }
        .sheet(item: $editingPlayer) { player in
            PlayerCardEditorSheet(
                player: player,
                teamName: team.name,
                accent: accent,
                isNumberDuplicated: player.number.map { duplicatedNumbers.contains($0) } ?? false,
                onRequestDelete: {
                    requestPlayerDeletion(player)
                }
            )
        }
        .confirmationDialog(
            "ロゴを削除しますか？",
            isPresented: $isShowingLogoDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) { deleteLogo() }
            Button("キャンセル", role: .cancel) { }
        }
        .confirmationDialog(
            "この選手を削除しますか？",
            isPresented: Binding(
                get: { playerPendingDeletion != nil },
                set: { if !$0 { playerPendingDeletion = nil } }
            ),
            presenting: playerPendingDeletion
        ) { player in
            Button("削除する", role: .destructive) {
                deletePlayer(player)
                playerPendingDeletion = nil
            }
            Button("キャンセル", role: .cancel) {
                playerPendingDeletion = nil
            }
        } message: { player in
            Text("「\(playerLabel(player))」を名簿から削除します。写真も消えます。")
        }
        .alert(
            "削除できません",
            isPresented: Binding(
                get: { deletionBlockedPlayer != nil },
                set: { if !$0 { deletionBlockedPlayer = nil } }
            ),
            presenting: deletionBlockedPlayer
        ) { _ in
            Button("OK", role: .cancel) {
                deletionBlockedPlayer = nil
            }
        } message: { player in
            Text("「\(playerLabel(player))」は試合の記録（得点・メンバー表・交代）で使われているため削除できません。")
        }
    }

    private var rosterBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.015, green: 0.035, blue: 0.065),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [accent.opacity(0.12), .clear, accent.opacity(0.05)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }

    private var teamIdentityCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.055))

            GenericTeamLines(accent: accent)
                .clipShape(RoundedRectangle(cornerRadius: 24))

            HStack(spacing: 18) {
                PhotosPicker(selection: $logoPickerItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        logoThumbnail

                        Image(systemName: "camera.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(accent)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 8) {
                    Text("チーム")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)

                    TextField("チーム名", text: $team.name)
                        .font(.title3.weight(.black))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.words)

                    Text("ロゴをタップして変更")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))

                    if team.logoPath != nil {
                        Button("ロゴを削除", role: .destructive) {
                            isShowingLogoDeleteConfirmation = true
                        }
                        .font(.caption.weight(.bold))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(accent.opacity(0.72), lineWidth: 1.25)
        )
        .shadow(color: accent.opacity(0.16), radius: 14, y: 8)
    }

    private var colorSelectionCard: some View {
        Button {
            isShowingColorPicker = true
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(team.colorHex == nil ? Color.clear : teamColor)
                    .frame(width: 46, height: 46)
                    .overlay(
                        Circle()
                            .stroke(team.colorHex == nil ? Color.white.opacity(0.35) : Color.white.opacity(0.62), lineWidth: 2)
                    )
                    .overlay {
                        if team.colorHex == nil {
                            Image(systemName: "circle.slash")
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("チームカラー")
                        .font(.headline.weight(.black))
                        .foregroundStyle(accent)
                    Text("\(selectedColorName)・カードの縁と背番号に使用")
                        .font(.caption)
                        .foregroundStyle(accent.opacity(0.72))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(18)
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(accent.opacity(0.48), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var rosterSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("選手名簿")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.white)
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule()
                                    .fill(accent)
                                    .frame(width: 13, height: 3)
                                    .rotationEffect(.degrees(-45))
                            }
                        }
                    }

                    Text("カードをタップして編集・データ確認")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.52))
                }

                Spacer()

                Text("\(registeredCount)/\(players.count)")
                    .font(.title3.weight(.black).monospacedDigit())
                    .foregroundStyle(accent)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(players) { player in
                    Button {
                        editingPlayer = player
                    } label: {
                        PlayerCollectionCard(
                            player: player,
                            accent: accent,
                            isNumberDuplicated: player.number.map { duplicatedNumbers.contains($0) } ?? false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(playerLabel(player))を編集")
                }
            }

            Button {
                addPlayerSlot()
            } label: {
                Label("選手を追加", systemImage: "plus")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [accent, teamColor.opacity(0.78)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: accent.opacity(0.22), radius: 10, y: 5)
            }
            .buttonStyle(.plain)

            Button {
                isShowingBulkKanaSheet = true
            } label: {
                Label("読みをまとめて入力", systemImage: "character.book.closed")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("名前は空欄のままでも記録できます。背番号は選手カードをタップして変更できます。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var logoThumbnail: some View {
        if let name = team.logoPath, let uiImage = ImageStorage.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.32))
                Image(systemName: "shield.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .frame(width: 104, height: 104)
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
        guard players.isEmpty else { return }
        for number in 1...15 {
            modelContext.insert(Player(teamID: team.id, number: number))
        }
        try? modelContext.save()
    }

    private func addPlayerSlot() {
        let nextNumber = (players.compactMap(\.number).max() ?? 0) + 1
        let player = Player(teamID: team.id, number: nextNumber)
        modelContext.insert(player)
        try? modelContext.save()
        editingPlayer = player
    }

    private func playerLabel(_ player: Player) -> String {
        let name = (player.name?.isEmpty == false) ? player.name! : "名前未設定"
        if let number = player.number { return "#\(number) \(name)" }
        return name
    }

    private func requestPlayerDeletion(_ player: Player) {
        editingPlayer = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if isPlayerUsedInRecords(player) {
                deletionBlockedPlayer = player
            } else {
                playerPendingDeletion = player
            }
        }
    }

    private func isPlayerUsedInRecords(_ player: Player) -> Bool {
        let playerID = player.id

        var eventDescriptor = FetchDescriptor<StatEvent>(
            predicate: #Predicate { $0.playerID == playerID }
        )
        eventDescriptor.fetchLimit = 1
        if (try? modelContext.fetch(eventDescriptor).first) != nil { return true }

        var lineupDescriptor = FetchDescriptor<MatchLineup>(
            predicate: #Predicate { $0.playerID == playerID }
        )
        lineupDescriptor.fetchLimit = 1
        if (try? modelContext.fetch(lineupDescriptor).first) != nil { return true }

        var substitutionDescriptor = FetchDescriptor<Substitution>(
            predicate: #Predicate { $0.playerInID == playerID || $0.playerOutID == playerID }
        )
        substitutionDescriptor.fetchLimit = 1
        return ((try? modelContext.fetch(substitutionDescriptor).first) != nil)
    }

    private func deletePlayer(_ player: Player) {
        if let photoName = player.imagePath {
            ImageStorage.delete(named: photoName)
        }
        modelContext.delete(player)
        try? modelContext.save()
    }
}

// MARK: - Reusable collection card

private struct PlayerCollectionCard: View {
    @Bindable var player: Player
    let accent: Color
    let isNumberDuplicated: Bool

    private var displayName: String {
        let trimmed = (player.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "名前未設定" : trimmed
    }

    private var romanName: String? {
        let trimmed = (player.nameRoman ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.uppercased()
    }

    var body: some View {
        GeometryReader { proxy in
            let cardShape = CollectionCardShape(cut: max(8, proxy.size.width * 0.075))
            let photoHeight = proxy.size.height * 0.76

            ZStack(alignment: .topLeading) {
                cardBackground

                playerPhoto(height: photoHeight)

                // 光沢は写真エリアまで。名前帯より先に描いて、黒帯が白く濁らないようにする
                glossOverlay

                VStack(spacing: 0) {
                    Spacer()
                    namePlate
                        .frame(height: proxy.size.height - photoHeight)
                }

                numberBadge
                    .padding(5)

                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                accent.withBrightness(min(1.0, accent.hsbBrightness + 0.12)),
                                accent.withBrightness(max(0.15, accent.hsbBrightness - 0.24))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .clipShape(cardShape)
            .overlay(cardShape.stroke(metallicBorder, lineWidth: 2.4))
            .overlay(cardShape.inset(by: 2.4).stroke(.white.opacity(0.5), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.45), radius: 6, y: 4)
            .shadow(color: accent.opacity(0.22), radius: 10, y: 2)
        }
        // 1:1 より名前欄の分だけ少し縦長。3列でも顔写真を大きく保つ。
        .aspectRatio(0.78, contentMode: .fit)
    }

    private var cardBackground: some View {
        ZStack {
            // モックのような明るい白銀ベース。暗い面を作らず艶は斜めストリークで出す
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.99, green: 0.99, blue: 1.00), location: 0.0),
                    .init(color: Color(red: 0.86, green: 0.88, blue: 0.91), location: 0.32),
                    .init(color: Color(red: 0.97, green: 0.97, blue: 0.99), location: 0.55),
                    .init(color: Color(red: 0.82, green: 0.84, blue: 0.88), location: 0.80),
                    .init(color: Color(red: 0.93, green: 0.94, blue: 0.96), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            CardTextureLines()

            // 枠のチームカラーが白銀面に映り込む気配(左上・右下だけ淡く)
            RadialGradient(
                colors: [accent.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 130
            )
            RadialGradient(
                colors: [accent.opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 150
            )
        }
    }

    /// トレカの箔のように、左上から斜めに走る光の帯。写真エリアに艶を足す。
    private var glossOverlay: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.50), location: 0.0),
                .init(color: .white.opacity(0.10), location: 0.16),
                .init(color: .white.opacity(0.0), location: 0.32),
                .init(color: .white.opacity(0.12), location: 0.50),
                .init(color: .white.opacity(0.0), location: 0.64)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    /// 深めのチームカラーでできた金属フレーム。ところどころに光の反射を入れる。
    private var metallicBorder: LinearGradient {
        let bright = accent.hsbBrightness
        return LinearGradient(
            stops: [
                .init(color: accent.withBrightness(max(0.12, bright - 0.18)), location: 0.0),
                .init(color: accent.withBrightness(min(1.0, bright + 0.16)), location: 0.22),
                .init(color: accent.withBrightness(max(0.10, bright - 0.32)), location: 0.50),
                .init(color: accent.withBrightness(min(1.0, bright + 0.10)), location: 0.76),
                .init(color: accent.withBrightness(max(0.10, bright - 0.28)), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func playerPhoto(height: CGFloat) -> some View {
        if let name = player.imagePath, let uiImage = ImageStorage.image(named: name) {
            if uiImage.hasTransparentPixels {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 3)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: height, alignment: .bottom)
            } else {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipped()
            }
        } else {
            VStack(spacing: 7) {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 34, weight: .medium))
                Text("写真を追加")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.black.opacity(0.38))
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
    }

    private var namePlate: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(romanName ?? "RUGBY AS")
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(accent.withBrightness(min(1.0, accent.hsbBrightness + 0.22)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // モックの名前帯はほぼ漆黒。チームカラーを混ぜると灰色に濁るので黒だけで作る
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.14), Color(white: 0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [.white.opacity(0.08), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(0.45))
                .frame(height: 0.8)
        }
    }

    private var numberBadge: some View {
        let base = isNumberDuplicated ? Color.orange : (player.number == nil ? Color.gray : accent)
        return Text(player.number.map { "#\($0)" } ?? "—")
            .font(.caption.weight(.black).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                // モックのバッジは枠より一段深い色。上端だけ光らせて沈んだ艶にする
                LinearGradient(
                    colors: [
                        base.withBrightness(min(1.0, base.hsbBrightness + 0.04)),
                        base.withBrightness(max(0.10, base.hsbBrightness - 0.16)),
                        base.withBrightness(max(0.08, base.hsbBrightness - 0.30))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(CollectionNumberBadgeShape())
            .overlay(CollectionNumberBadgeShape().stroke(.white.opacity(0.28), lineWidth: 0.6))
    }
}

private struct CollectionCardShape: InsettableShape {
    var cut: CGFloat = 10
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = min(cut, min(r.width, r.height) * 0.18)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> CollectionCardShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct CollectionNumberBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.72))
        path.addLine(to: CGPoint(x: rect.maxX * 0.80, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CardTextureLines: View {
    /// 左下→右上の斜め線を spacing 間隔で敷き詰める共通パス
    private func diagonalLines(in size: CGSize, spacing: CGFloat, phase: CGFloat = 0) -> Path {
        Path { path in
            var x: CGFloat = -size.height + phase
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 幅広のぼかした白帯 = ブラシ地金の「面」の艶
                diagonalLines(in: proxy.size, spacing: 34)
                    .stroke(Color.white.opacity(0.55), lineWidth: 9)
                    .blur(radius: 6)

                // 細い白すじ = ヘアライン
                diagonalLines(in: proxy.size, spacing: 12)
                    .stroke(Color.white.opacity(0.45), lineWidth: 0.7)

                // ごく薄い影のすじで金属の目に深みを出す
                diagonalLines(in: proxy.size, spacing: 21, phase: 6)
                    .stroke(Color.black.opacity(0.07), lineWidth: 1.4)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GenericTeamLines: View {
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.16), .clear, accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Path { path in
                    let startX = proxy.size.width * 0.70
                    for index in 0..<5 {
                        let offset = CGFloat(index) * 12
                        path.move(to: CGPoint(x: startX + offset, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.34 + offset))
                    }
                }
                .stroke(accent.opacity(0.26), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Team color picker

private struct TeamColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var team: Team

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    colorButton(hex: nil, name: "未設定")
                    ForEach(TeamColorPalette.options) { option in
                        colorButton(hex: option.hex, name: option.name)
                    }
                }
                .padding(18)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("チームカラー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func colorButton(hex: String?, name: String) -> some View {
        let isSelected = team.colorHex == hex
        return Button {
            team.colorHex = hex
            try? modelContext.save()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 74)

                    if let hex, let color = Color(hex: hex) {
                        Circle()
                            .fill(color)
                            .frame(width: 44, height: 44)
                            .shadow(color: color.opacity(0.38), radius: 8)
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [4]))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "circle.slash")
                                    .foregroundStyle(.white.opacity(0.55))
                            )
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.black))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(7)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                )

                Text(name)
                    .font(.caption.weight(isSelected ? .black : .semibold))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Player editor

// MARK: - 読みの一括入力

// 選手が多いとき、1人ずつカードを開かずに読み(かな)をまとめて入力する画面。
// 保存時に英語表記も自動生成する(手で直した英語表記は上書きしない)。
private struct BulkKanaInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // 入力途中の値を保持する下書き。保存を押すまで選手データには触らない。
    private struct KanaDraft: Identifiable {
        let id: UUID
        let label: String
        let originalKana: String
        let originalRoman: String
        var kana: String

        // 英語表記が「空」か「元の読みからの自動生成のまま」なら、保存時に追従して作り直す
        var willAutoFillRoman: Bool {
            originalRoman.isEmpty || originalRoman == PlayerNameRomanizer.roman(fromKana: originalKana)
        }
    }

    private let players: [Player]
    private let accent: Color
    @State private var drafts: [KanaDraft]
    @FocusState private var focusedID: UUID?

    init(players: [Player], accent: Color) {
        self.players = players
        self.accent = accent
        self._drafts = State(initialValue: players.map { player in
            let name = (player.name?.isEmpty == false) ? player.name! : "名前未設定"
            let label = player.number.map { "#\($0) \(name)" } ?? name
            return KanaDraft(
                id: player.id,
                label: label,
                originalKana: player.nameKana ?? "",
                originalRoman: player.nameRoman ?? "",
                kana: player.nameKana ?? ""
            )
        })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.02, green: 0.04, blue: 0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        Text("読み(かな)を入れると、保存時にカードの英語表記が自動で入ります。キーボードの「次へ」で下の選手に移動できます。")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 4)

                        ForEach($drafts) { $draft in
                            draftRow($draft)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("読みをまとめて入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveAndDismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func draftRow(_ draft: Binding<KanaDraft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.wrappedValue.label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)

            TextField("やまだ たろう", text: draft.kana)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .focused($focusedID, equals: draft.wrappedValue.id)
                .submitLabel(.next)
                .onSubmit { focusNext(after: draft.wrappedValue.id) }

            romanPreview(draft.wrappedValue)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func romanPreview(_ draft: KanaDraft) -> some View {
        let trimmedKana = draft.kana.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.willAutoFillRoman {
            let generated = PlayerNameRomanizer.roman(fromKana: trimmedKana)
            if !generated.isEmpty {
                Text(generated)
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundStyle(accent)
            }
        } else {
            Text("\(draft.originalRoman)(手動設定のため保持)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func focusNext(after id: UUID) {
        guard let index = drafts.firstIndex(where: { $0.id == id }),
              index + 1 < drafts.count else {
            focusedID = nil
            return
        }
        focusedID = drafts[index + 1].id
    }

    private func saveAndDismiss() {
        let playersByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        for draft in drafts {
            guard let player = playersByID[draft.id] else { continue }
            let trimmedKana = draft.kana.trimmingCharacters(in: .whitespacesAndNewlines)
            player.nameKana = trimmedKana.isEmpty ? nil : trimmedKana

            if draft.willAutoFillRoman {
                let generated = PlayerNameRomanizer.roman(fromKana: trimmedKana)
                player.nameRoman = generated.isEmpty ? nil : generated
            }
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - かな→英語表記の自動変換

enum PlayerNameRomanizer {
    /// 読み(かな)から英語表記を作る。「ますだ ゆい」→「YUI MASUDA」。
    /// 日本語の姓名順を英語の「名 姓」順にひっくり返す。1語ならそのまま。
    /// 外国人選手など順序や綴りが違う場合は、生成後に手で直せる前提の下書き。
    static func roman(fromKana kana: String) -> String {
        // 「・」や全角スペースも区切りとして扱う
        let normalized = kana
            .replacingOccurrences(of: "・", with: " ")
            .replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        // かな→ローマ字。「ゆう」→「yū」のような長音記号は普通の英字に畳む
        let latin = normalized.applyingTransform(.toLatin, reverse: false) ?? normalized
        let folded = latin.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))

        let words = folded
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.uppercased() }
        return words.reversed().joined(separator: " ")
    }
}

private struct PlayerCardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var player: Player
    let teamName: String
    let accent: Color
    let isNumberDuplicated: Bool
    let onRequestDelete: () -> Void

    @State private var nameText: String
    @State private var kanaText: String
    @State private var romanText: String
    @State private var numberText: String
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isShowingPhotoDeleteConfirmation = false
    @State private var isRemovingBackground = false
    @State private var backgroundRemovalError: String?

    init(
        player: Player,
        teamName: String,
        accent: Color,
        isNumberDuplicated: Bool,
        onRequestDelete: @escaping () -> Void
    ) {
        self._player = Bindable(wrappedValue: player)
        self.teamName = teamName
        self.accent = accent
        self.isNumberDuplicated = isNumberDuplicated
        self.onRequestDelete = onRequestDelete
        self._nameText = State(initialValue: player.name ?? "")
        self._kanaText = State(initialValue: player.nameKana ?? "")
        self._romanText = State(initialValue: player.nameRoman ?? "")
        self._numberText = State(initialValue: player.number.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.02, green: 0.04, blue: 0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        PlayerCollectionCard(
                            player: player,
                            accent: accent,
                            isNumberDuplicated: isNumberDuplicated
                        )
                        .frame(width: 240)

                        editorFields
                        photoActions
                        statsLink
                        deleteButton
                    }
                    .padding(18)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("選手詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveAndDismiss() }
                        .fontWeight(.bold)
                        .foregroundStyle(accent)
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                handleSelectedPhoto(newItem)
            }
            .onChange(of: kanaText) { oldKana, newKana in
                // 英語表記を手で直した後は上書きしない。
                // 空、または「直す前の読みから自動生成した値のまま」のときだけ追従させる。
                let autoFromOld = PlayerNameRomanizer.roman(fromKana: oldKana)
                if romanText.isEmpty || romanText == autoFromOld {
                    romanText = PlayerNameRomanizer.roman(fromKana: newKana)
                }
            }
            .confirmationDialog(
                "写真を削除しますか？",
                isPresented: $isShowingPhotoDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("削除する", role: .destructive) { deletePhoto() }
                Button("キャンセル", role: .cancel) { }
            }
            .alert("背景を削除できませんでした", isPresented: Binding(
                get: { backgroundRemovalError != nil },
                set: { if !$0 { backgroundRemovalError = nil } }
            )) {
                Button("OK", role: .cancel) { backgroundRemovalError = nil }
            } message: {
                Text(backgroundRemovalError ?? "人物がはっきり写った写真で再度お試しください。")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var editorFields: some View {
        VStack(spacing: 0) {
            fieldRow(title: "背番号") {
                TextField("未設定", text: $numberText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(isNumberDuplicated ? Color.orange : Color.white)
            }

            Divider().overlay(Color.white.opacity(0.10))

            fieldRow(title: "名前") {
                TextField("名前（任意）", text: $nameText)
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
            }

            Divider().overlay(Color.white.opacity(0.10))

            fieldRow(title: "読み") {
                TextField("やまだ たろう", text: $kanaText)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
            }

            Divider().overlay(Color.white.opacity(0.10))

            fieldRow(title: "英語表記") {
                TextField("読みから自動で入力", text: $romanText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.white)
            }

            Text("読み(かな)を入力すると英語表記が自動で入ります。カードの名前の下に表示されるので、綴りが違うときは英語表記を直接直してください。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)

            if isNumberDuplicated {
                Text("同じ背番号の選手が登録されています。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func fieldRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 58, alignment: .leading)
            content()
        }
        .frame(minHeight: 48)
    }

    private var photoActions: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Label(player.imagePath == nil ? "写真を追加" : "写真を変更", systemImage: "photo")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)

            if player.imagePath != nil {
                Button {
                    removePhotoBackground()
                } label: {
                    HStack(spacing: 9) {
                        if isRemovingBackground {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(isRemovingBackground ? "背景を削除中…" : "背景を自動で削除")
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(accent.opacity(0.84))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .disabled(isRemovingBackground)

                Button("写真を削除", role: .destructive) {
                    isShowingPhotoDeleteConfirmation = true
                }
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
            }

            Text("背景削除後は透明PNGとして保存され、カードの共通背景に自然に重なります。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsLink: some View {
        NavigationLink {
            PlayerDetailView(player: player)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("個人成績を見る")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("試合別・大会別の記録を確認")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.42))
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            onRequestDelete()
            dismiss()
        } label: {
            Label("選手を削除", systemImage: "trash")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private func saveAndDismiss() {
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        player.name = trimmedName.isEmpty ? nil : trimmedName

        let trimmedKana = kanaText.trimmingCharacters(in: .whitespacesAndNewlines)
        player.nameKana = trimmedKana.isEmpty ? nil : trimmedKana

        let trimmedRoman = romanText.trimmingCharacters(in: .whitespacesAndNewlines)
        player.nameRoman = trimmedRoman.isEmpty ? nil : trimmedRoman

        let trimmedNumber = numberText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNumber.isEmpty {
            player.number = nil
        } else if let number = Int(trimmedNumber), number > 0 {
            player.number = number
        }

        try? modelContext.save()
        dismiss()
    }

    private func handleSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                if let data, let newName = ImageStorage.save(data) {
                    replacePhoto(with: newName)
                }
                photoPickerItem = nil
            }
        }
    }

    private func removePhotoBackground() {
        guard !isRemovingBackground,
              let name = player.imagePath,
              let image = ImageStorage.image(named: name),
              let sourceData = image.pngData() else { return }

        isRemovingBackground = true
        Task {
            let outputData = await Task.detached(priority: .userInitiated) {
                try? ForegroundBackgroundRemover.removeBackground(from: sourceData)
            }.value

            await MainActor.run {
                defer { isRemovingBackground = false }
                guard let outputData, let newName = ImageStorage.savePNG(outputData) else {
                    backgroundRemovalError = "人物の輪郭を検出できませんでした。人物が大きく、背景との区別がつきやすい写真で再度お試しください。"
                    return
                }
                replacePhoto(with: newName)
            }
        }
    }

    private func replacePhoto(with newName: String) {
        if let oldName = player.imagePath {
            ImageStorage.delete(named: oldName)
        }
        player.imagePath = newName
        try? modelContext.save()
    }

    private func deletePhoto() {
        if let name = player.imagePath {
            ImageStorage.delete(named: name)
        }
        player.imagePath = nil
        try? modelContext.save()
    }
}

// MARK: - Background removal

private enum ForegroundBackgroundRemover {
    static func removeBackground(from data: Data) throws -> Data {
        guard let image = UIImage(data: data),
              let inputImage = CIImage(image: image, options: [.applyOrientationProperty: true]) else {
            throw BackgroundRemovalError.invalidImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: inputImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw BackgroundRemovalError.noForeground
        }

        let maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        let transparentBackground = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: inputImage.extent)

        let outputImage = inputImage.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: transparentBackground,
                kCIInputMaskImageKey: maskImage
            ]
        )

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(outputImage, from: inputImage.extent) else {
            throw BackgroundRemovalError.renderFailed
        }

        let output = UIImage(cgImage: cgImage)
        guard let pngData = output.pngData() else {
            throw BackgroundRemovalError.renderFailed
        }
        return pngData
    }

    private enum BackgroundRemovalError: Error {
        case invalidImage
        case noForeground
        case renderFailed
    }
}

private extension UIImage {
    var hasTransparentPixels: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else { return false }
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
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
        MatchLineup.self,
        Substitution.self
    ], inMemory: true)
}
