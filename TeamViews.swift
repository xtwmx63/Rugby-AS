//
//  TeamViews.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import PhotosUI
import SwiftData
import SwiftUI

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

/// チームカラーの選択肢。極端に濃い/薄い色や、対戦時に区別しづらい色を避けた
/// 視認性の高い 29 色のパレット。
struct TeamColorOption: Identifiable, Hashable {
    let hex: String
    let name: String
    var id: String { hex }
    var color: Color { Color(hex: hex) ?? .gray }
}

enum TeamColorPalette {
    // スペクトラム順（赤 → 橙 → 黄 → 緑 → 青緑 → 青 → 紫 → 桃 → 茶 → 中性）に並べる。
    // 視認性確保のため、彩度・明度はどれも中〜やや濃いめのトーンに揃えている。
    // 29 色（未設定と合わせて 5×6 グリッド）。
    static let options: [TeamColorOption] = [
        // 赤系
        .init(hex: "#B71C1C", name: "クリムゾン"),
        .init(hex: "#E53935", name: "レッド"),
        .init(hex: "#FF7043", name: "コーラル"),
        .init(hex: "#FF8A65", name: "サーモン"),

        // 橙系
        .init(hex: "#EF6C00", name: "パンプキン"),
        .init(hex: "#FB8C00", name: "オレンジ"),
        .init(hex: "#FFB300", name: "アンバー"),

        // 黄系
        .init(hex: "#FDD835", name: "イエロー"),
        .init(hex: "#827717", name: "オリーブ"),

        // 緑系
        .init(hex: "#C0CA33", name: "ライム"),
        .init(hex: "#43A047", name: "グリーン"),
        .init(hex: "#1B5E20", name: "フォレスト"),
        .init(hex: "#4DB6AC", name: "ミント"),

        // 青緑系
        .init(hex: "#00897B", name: "ティール"),
        .init(hex: "#00ACC1", name: "シアン"),
        .init(hex: "#26C6DA", name: "アクア"),

        // 青系
        .init(hex: "#29B6F6", name: "スカイ"),
        .init(hex: "#1E88E5", name: "ブルー"),
        .init(hex: "#3949AB", name: "ネイビー"),
        .init(hex: "#5C6BC0", name: "インディゴ"),

        // 紫系
        .init(hex: "#9575CD", name: "ラベンダー"),
        .init(hex: "#8E24AA", name: "パープル"),
        .init(hex: "#6A1B9A", name: "プラム"),

        // 桃系
        .init(hex: "#BA1FAB", name: "マゼンタ"),
        .init(hex: "#D81B60", name: "ピンク"),
        .init(hex: "#EC407A", name: "ローズピンク"),

        // 茶系
        .init(hex: "#6D4C41", name: "ブラウン"),
        .init(hex: "#A1887F", name: "キャメル"),

        // 中性
        .init(hex: "#546E7A", name: "スレート")
    ]

    /// AWAY 用の色を返す。
    /// - RGB 距離が `minDistance` 以上、かつ色相距離が `minHueDistance` 以上であれば
    ///   ユーザの選んだ色 (preferred) をそのまま採用。
    /// - どちらかが満たせない場合、パレットから両条件を満たす中で preferred に
    ///   一番近い色へ差し替える。
    static func nearestDistinct(
        from preferred: Color,
        against home: Color,
        minDistance: Double,
        minHueDistance: Double = 0.04
    ) -> Color {
        let rgbOK = home.rgbDistance(to: preferred) >= minDistance
        let hueOK = home.hueDistance(to: preferred) >= minHueDistance
        if rgbOK && hueOK {
            return preferred
        }

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

        if let best = bestColor { return best }

        var fallback = preferred
        var fallbackDistance: Double = 0
        for option in options {
            let distance = home.rgbDistance(to: option.color)
            if distance > fallbackDistance {
                fallbackDistance = distance
                fallback = option.color
            }
        }
        return fallback
    }
}

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

    // チーム内で重複している背番号(行にオレンジで警告表示)
    private var duplicatedNumbers: Set<Int> {
        var seen: Set<Int> = []
        var duplicated: Set<Int> = []
        for player in players where !seen.insert(player.number).inserted {
            duplicated.insert(player.number)
        }
        return duplicated
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
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                    spacing: 14
                ) {
                    teamColorSwatch(hex: nil, name: "未設定")
                    ForEach(TeamColorPalette.options) { option in
                        teamColorSwatch(hex: option.hex, name: option.name)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("チームカラー")
            } footer: {
                Text("サマリー画面の比較表示でチームの色として使われます。記録画面の色は変わりません。")
            }

            Section {
                ForEach(players) { player in
                    PlayerRow(
                        player: player,
                        isNumberDuplicated: duplicatedNumbers.contains(player.number)
                    )
                }

                Button {
                    addPlayerSlot()
                } label: {
                    Label("追加", systemImage: "plus")
                }
            } header: {
                Text("選手名簿")
            } footer: {
                Text("名前は空欄のままでも記録できます。背番号はタップで変更でき、大会前にここで設定しておけば、以後の試合のメンバー登録にそのまま引き継がれます。")
            }
        }
        .navigationTitle(team.name.isEmpty ? "チーム編集" : team.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ensureInitialPlayers()
        }
        .onChange(of: logoPickerItem) { _, newItem in
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
    private func teamColorSwatch(hex: String?, name: String) -> some View {
        let isSelected = team.colorHex == hex
        Button {
            team.colorHex = hex
            try? modelContext.save()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if let hex, let color = Color(hex: hex) {
                        Circle()
                            .fill(color)
                    } else {
                        Circle()
                            .stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                            .background(Circle().fill(Color(.systemBackground)))
                            .overlay(
                                Image(systemName: "circle.slash")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            )
                    }
                    if isSelected {
                        Circle()
                            .stroke(Color.primary, lineWidth: 3)
                    }
                }
                .frame(width: 40, height: 40)

                Text(name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
    // チーム内で背番号が重複しているとき true(オレンジで警告表示)
    var isNumberDuplicated: Bool = false
    @Environment(\.modelContext) private var modelContext
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isShowingPhotoDeleteConfirmation = false
    @State private var isEditingNumber = false
    @State private var numberText = ""

    var body: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                photoThumbnail
            }
            .buttonStyle(.plain)

            // 背番号はタップで変更(大会前にここで事前登録しておく)
            Button {
                numberText = "\(player.number)"
                isEditingNumber = true
            } label: {
                Text("#\(player.number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isNumberDuplicated ? Color.orange : Color.accentColor)
            }
            .buttonStyle(.plain)
            .frame(width: 44, alignment: .leading)

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

            // 個人成績の画面へ(名前入力の邪魔をしないよう、専用ボタンで)
            NavigationLink {
                PlayerDetailView(player: player)
            } label: {
                Image(systemName: "chart.bar.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .frame(width: 30)
            .accessibilityLabel("個人成績を見る")
        }
        .onChange(of: photoPickerItem) { _, newItem in
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
        .alert("背番号を変更", isPresented: $isEditingNumber) {
            TextField("番号", text: $numberText)
                .keyboardType(.numberPad)
            Button("保存") {
                if let number = Int(numberText), number > 0 {
                    player.number = number
                    try? modelContext.save()
                }
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("この選手の背番号を入力してください。以後の試合のメンバー登録に自動で使われます。")
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
