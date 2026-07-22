//
//  TournamentEditorView.swift
//  Rugby AS
//
//  大会の作成・編集シート。名前・年度・ロゴ・7人制/15人制・フォーマット・
//  出場チームをまとめて設定する。値は @Bindable でその場で反映し、
//  「保存」で確定して閉じる。すべて任意（名前以外は空でよい）。
//

import PhotosUI
import SwiftData
import SwiftUI

struct TournamentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var tournament: Tournament
    @Query(sort: \Team.name) private var allTeams: [Team]

    @State private var nameText: String
    @State private var selectedYear: Int?
    @State private var variantRaw: String?
    @State private var formatRaw: String?
    @State private var participatingIDs: Set<UUID>
    @State private var logoPickerItem: PhotosPickerItem?

    init(tournament: Tournament) {
        self._tournament = Bindable(wrappedValue: tournament)
        self._nameText = State(initialValue: tournament.officialName)
        self._selectedYear = State(initialValue: tournament.year)
        self._variantRaw = State(initialValue: tournament.variantRaw)
        self._formatRaw = State(initialValue: tournament.formatRaw)
        self._participatingIDs = State(initialValue: Set(tournament.teamIDs))
    }

    // 年度の候補（今年を中心に前後）
    private var yearOptions: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 10)...(current + 1)).reversed()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("大会") {
                    TextField("大会の正式名称", text: $nameText)

                    Picker("年度", selection: $selectedYear) {
                        Text("未設定").tag(Int?.none)
                        ForEach(yearOptions, id: \.self) { year in
                            Text("\(String(year))年").tag(Int?.some(year))
                        }
                    }
                }

                Section("ロゴ") {
                    HStack(spacing: 14) {
                        logoThumbnail
                        PhotosPicker(selection: $logoPickerItem, matching: .images) {
                            Label(tournament.logoPath == nil ? "ロゴを追加" : "ロゴを変更", systemImage: "photo")
                        }
                        if tournament.logoPath != nil {
                            Spacer()
                            Button(role: .destructive) {
                                deleteLogo()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }

                Section("形式") {
                    Picker("人数", selection: $variantRaw) {
                        Text("未設定").tag(String?.none)
                        ForEach(RugbyVariant.allCases) { variant in
                            Text(variant.displayName).tag(String?.some(variant.rawValue))
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("フォーマット", selection: $formatRaw) {
                        Text("未設定").tag(String?.none)
                        ForEach(TournamentFormat.allCases) { format in
                            Text(format.displayName).tag(String?.some(format.rawValue))
                        }
                    }
                }

                Section {
                    if allTeams.isEmpty {
                        Text("先にチームを登録してください。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(allTeams) { team in
                            Button {
                                toggle(team.id)
                            } label: {
                                HStack {
                                    Image(systemName: participatingIDs.contains(team.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(participatingIDs.contains(team.id) ? Color.accentColor : Color.secondary)
                                    Text(team.name)
                                        .foregroundStyle(.primary)
                                    if let category = team.category, !category.isEmpty {
                                        Text(category)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                } header: {
                    Text("出場チーム（\(participatingIDs.count)）")
                } footer: {
                    Text("この大会に出場するチームを選びます。試合を記録していないチームも登録できます。")
                }
            }
            .navigationTitle("大会の設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.bold)
                }
            }
            .onChange(of: logoPickerItem) { _, newItem in
                handleSelectedLogo(newItem)
            }
        }
    }

    @ViewBuilder
    private var logoThumbnail: some View {
        if let name = tournament.logoPath, let uiImage = ImageStorage.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
                .frame(width: 52, height: 52)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func toggle(_ id: UUID) {
        if participatingIDs.contains(id) {
            participatingIDs.remove(id)
        } else {
            participatingIDs.insert(id)
        }
    }

    private func save() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        tournament.officialName = trimmed.isEmpty ? "大会名未設定" : trimmed
        tournament.year = selectedYear
        tournament.variantRaw = variantRaw
        tournament.formatRaw = formatRaw
        tournament.teamIDs = Array(participatingIDs)
        try? modelContext.save()
        dismiss()
    }

    private func handleSelectedLogo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                if let data, let newName = ImageStorage.save(data) {
                    if let oldName = tournament.logoPath {
                        ImageStorage.delete(named: oldName)
                    }
                    tournament.logoPath = newName
                    try? modelContext.save()
                }
                logoPickerItem = nil
            }
        }
    }

    private func deleteLogo() {
        if let name = tournament.logoPath {
            ImageStorage.delete(named: name)
        }
        tournament.logoPath = nil
        try? modelContext.save()
    }
}
