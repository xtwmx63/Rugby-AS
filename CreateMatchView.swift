//
//  CreateMatchView.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import SwiftData
import SwiftUI

struct CreateMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tournament.officialName) private var tournaments: [Tournament]
    @Query(sort: \Team.name) private var teams: [Team]

    @AppStorage("lastMatchDateTimestamp") private var lastMatchDateTimestamp = Date().timeIntervalSince1970
    // 設定画面で入力した自チーム名。ホームチームの初期値に使う
    @AppStorage("defaultTeamName") private var defaultTeamName = ""

    @State private var selectedTournamentID: UUID?
    @State private var newTournamentName = ""
    @State private var selectedHomeTeamID: UUID?
    @State private var newHomeTeamName = ""
    @State private var selectedAwayTeamID: UUID?
    @State private var newAwayTeamName = ""
    @State private var playedAt = Date()
    @State private var alertTitle = ""
    @State private var alertMessage: String?
    @State private var recordingMatch: Match?
    @State private var quickResultMatch: Match?

    var body: some View {
        Form {
            Section("大会") {
                Picker("大会", selection: $selectedTournamentID) {
                    Text("新規作成").tag(UUID?.none)
                    ForEach(tournaments) { tournament in
                        Text(tournament.officialName).tag(Optional(tournament.id))
                    }
                }

                if selectedTournamentID == nil {
                    TextField("大会の正式名称", text: $newTournamentName)
                }
            }

            Section("チーム") {
                TeamSelectionFields(
                    title: "ホーム",
                    selectedTeamID: $selectedHomeTeamID,
                    newTeamName: $newHomeTeamName,
                    teams: teams
                )

                TeamSelectionFields(
                    title: "アウェイ",
                    selectedTeamID: $selectedAwayTeamID,
                    newTeamName: $newAwayTeamName,
                    teams: teams
                )
            }

            Section("試合日") {
                DatePicker("日付", selection: $playedAt, displayedComponents: .date)
            }

            Section {
                Button("保存") {
                    saveMatch(then: .close)
                }
                .disabled(!canSave)

                Button("保存して記録開始（詳細）") {
                    saveMatch(then: .detailedRecording)
                }
                .disabled(!canSave)
            } footer: {
                Text("「詳細」はポゼッションなども計測する記録画面へ、「結果だけ入力」は得点経過だけを手早く登録します（あとでどちらも追記できます）。")
            }

            Section {
                Button("保存して結果だけ入力（簡易）") {
                    saveMatch(then: .quickResult)
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle("試合をつくる")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
        .onAppear {
            playedAt = Date(timeIntervalSince1970: lastMatchDateTimestamp)
            applyDefaultTeamNameIfNeeded()
        }
        .alert(alertTitle, isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "入力内容を確認してください。")
        }
        .navigationDestination(item: $recordingMatch) { match in
            // 記録の前にスタメン/リザーブを登録する画面を挟む。
            // この画面の「保存」で V3RecordingView へ遷移する。
            LineupRegistrationView(match: match)
        }
        .navigationDestination(item: $quickResultMatch) { match in
            QuickResultEntryView(match: match)
        }
    }

    // 保存後の遷移先
    private enum SaveDestination {
        case close
        case detailedRecording
        case quickResult
    }

    // 設定の自チーム名をホームチームに最初から入れておく(毎回入力させない)。
    // 既に同名のチームが登録済みならそれを選択、なければ新規名として入れる。
    private func applyDefaultTeamNameIfNeeded() {
        let name = trimmed(defaultTeamName)
        guard !name.isEmpty,
              selectedHomeTeamID == nil,
              trimmed(newHomeTeamName).isEmpty else { return }

        if let existing = teams.first(where: { $0.name == name }) {
            selectedHomeTeamID = existing.id
        } else {
            newHomeTeamName = name
        }
    }

    private var canSave: Bool {
        hasTournament && hasHomeTeam && hasAwayTeam && isDifferentTeamSelection
    }

    private var hasTournament: Bool {
        selectedTournamentID != nil || !trimmed(newTournamentName).isEmpty
    }

    private var hasHomeTeam: Bool {
        selectedHomeTeamID != nil || !trimmed(newHomeTeamName).isEmpty
    }

    private var hasAwayTeam: Bool {
        selectedAwayTeamID != nil || !trimmed(newAwayTeamName).isEmpty
    }

    private var isDifferentTeamSelection: Bool {
        if let selectedHomeTeamID, let selectedAwayTeamID {
            return selectedHomeTeamID != selectedAwayTeamID
        }
        return true
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    alertMessage = nil
                }
            }
        )
    }

    private func saveMatch(then destination: SaveDestination) {
        guard canSave else {
            showAlert(title: "保存できませんでした", message: "大会、ホームチーム、アウェイチームを入力してください。")
            return
        }

        let tournament = selectedTournament() ?? createTournament()
        let homeTeam = selectedTeam(id: selectedHomeTeamID) ?? createTeam(name: trimmed(newHomeTeamName))
        let awayTeam = selectedTeam(id: selectedAwayTeamID) ?? createTeam(name: trimmed(newAwayTeamName))

        guard homeTeam.id != awayTeam.id else {
            showAlert(title: "保存できませんでした", message: "ホームとアウェイには別のチームを選んでください。")
            return
        }

        let match = Match(
            tournamentID: tournament.id,
            homeTeamID: homeTeam.id,
            awayTeamID: awayTeam.id,
            playedAt: playedAt
        )
        modelContext.insert(match)
        lastMatchDateTimestamp = playedAt.timeIntervalSince1970

        do {
            try modelContext.save()
            switch destination {
            case .close:
                dismiss()
            case .detailedRecording:
                recordingMatch = match
            case .quickResult:
                quickResultMatch = match
            }
        } catch {
            showAlert(title: "保存できませんでした", message: "保存中にエラーが起きました。")
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
    }

    private func selectedTournament() -> Tournament? {
        guard let selectedTournamentID else { return nil }
        return tournaments.first { $0.id == selectedTournamentID }
    }

    private func selectedTeam(id: UUID?) -> Team? {
        guard let id else { return nil }
        return teams.first { $0.id == id }
    }

    private func createTournament() -> Tournament {
        let tournament = Tournament(officialName: trimmed(newTournamentName))
        modelContext.insert(tournament)
        return tournament
    }

    private func createTeam(name: String) -> Team {
        let team = Team(name: name)
        modelContext.insert(team)
        for number in 1...15 {
            modelContext.insert(Player(teamID: team.id, number: number))
        }
        return team
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TeamSelectionFields: View {
    let title: String
    @Binding var selectedTeamID: UUID?
    @Binding var newTeamName: String
    let teams: [Team]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: $selectedTeamID) {
                Text("新規作成").tag(UUID?.none)
                ForEach(teams) { team in
                    Text(team.name).tag(Optional(team.id))
                }
            }

            if selectedTeamID == nil {
                TextField("\(title)チーム名", text: $newTeamName)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CreateMatchView()
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
