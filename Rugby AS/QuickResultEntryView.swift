//
//  QuickResultEntryView.swift
//  Rugby AS
//
//  「簡易記録」：試合を細かく計測せず、得点経過(時間・チーム・種類・選手)だけを
//  1行ずつ入力して結果を登録する画面。すでに終わった試合の入力に使う。
//
//  ここで入れた得点は通常の StatEvent として保存されるので、スコアは
//  常にイベントから再計算され、あとで詳細記録画面を開いて分析を足せる。
//  この画面が扱うのは「成功した得点」だけ。失敗キック(outcome=fail)など
//  詳細記録で入れたデータには触れない。
//

import SwiftData
import SwiftUI

struct QuickResultEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let match: Match
    @Query private var teams: [Team]
    @Query(sort: \Player.number) private var allPlayers: [Player]
    @Query private var matchEvents: [StatEvent]

    @State private var rows: [ScoreRow] = []
    @State private var didLoad = false

    init(match: Match) {
        self.match = match
        let matchID = match.id
        _matchEvents = Query(filter: #Predicate<StatEvent> { $0.matchID == matchID })
    }

    // 画面内で編集する1得点ぶんの下書き
    private struct ScoreRow: Identifiable {
        let id: UUID
        var isHome: Bool
        var category: ScoringCategory
        var half: Int          // 0 = 前半, 1 = 後半
        var minute: Int
        var playerID: UUID?
        let existingEventID: UUID?   // 既存イベントを編集中なら、その id
    }

    var body: some View {
        List {
            scoreHeaderSection
            rowsSection
            addSection
        }
        .navigationTitle("得点を入力")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { save() }
                    .fontWeight(.bold)
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Sections

    private var scoreHeaderSection: some View {
        Section {
            VStack(spacing: 6) {
                Text("\(liveScore(home: true)) - \(liveScore(home: false))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                HStack {
                    Text(teamName(match.homeTeamID))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(teamName(match.awayTeamID))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    halfScoreLabel("前半", half: 0)
                    halfScoreLabel("後半", half: 1)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var rowsSection: some View {
        if rows.isEmpty {
            Section {
                Text("下の「得点を追加」から、得点経過を1つずつ入力します。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("得点経過") {
                ForEach($rows) { $row in
                    scoreRowEditor($row)
                }
                .onDelete { offsets in
                    rows.remove(atOffsets: offsets)
                }
            }
        }
    }

    private var addSection: some View {
        Section {
            Button {
                addRow()
            } label: {
                Label("得点を追加", systemImage: "plus.circle.fill")
            }
        } footer: {
            Text("スコアは入力した得点から自動計算されます。あとで記録画面を開けば、ポゼッションなどの詳細分析も足せます。")
        }
    }

    private func scoreRowEditor(_ row: Binding<ScoreRow>) -> some View {
        let value = row.wrappedValue
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                // チーム
                Menu {
                    Button(teamName(match.homeTeamID)) { setTeam(row, isHome: true) }
                    Button(teamName(match.awayTeamID)) { setTeam(row, isHome: false) }
                } label: {
                    chip(value.isHome ? "HOME" : "AWAY", tint: value.isHome ? .blue : .red)
                }

                // 種類
                Menu {
                    ForEach(ScoringCategory.allCases, id: \.self) { category in
                        Button(category.displayName) { row.wrappedValue.category = category }
                    }
                } label: {
                    chip(value.category.displayName, tint: .green)
                }

                // 前半/後半
                Menu {
                    Button("前半") { row.wrappedValue.half = 0 }
                    Button("後半") { row.wrappedValue.half = 1 }
                } label: {
                    chip(value.half == 1 ? "後半" : "前半", tint: .gray)
                }

                // 分
                HStack(spacing: 2) {
                    TextField("分", value: row.minute, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 34)
                    Text("分").font(.caption).foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(value.category.points)点")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            // 選手(任意)
            Menu {
                Button("未設定") { row.wrappedValue.playerID = nil }
                ForEach(players(isHome: value.isHome)) { player in
                    Button(playerLabel(player)) { row.wrappedValue.playerID = player.id }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill").font(.caption)
                    Text(value.playerID.flatMap { id in players(isHome: value.isHome).first { $0.id == id } }.map(playerLabel) ?? "選手 未設定")
                        .foregroundStyle(value.playerID == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.15))
            .clipShape(Capsule())
    }

    private func halfScoreLabel(_ label: String, half: Int) -> some View {
        Text("\(label) \(liveScore(home: true, half: half))-\(liveScore(home: false, half: half))")
    }

    // MARK: - Derived

    private func liveScore(home: Bool, half: Int? = nil) -> Int {
        rows
            .filter { $0.isHome == home && (half == nil || $0.half == half) }
            .reduce(0) { $0 + $1.category.points }
    }

    private func players(isHome: Bool) -> [Player] {
        let teamID = isHome ? match.homeTeamID : match.awayTeamID
        return allPlayers
            .filter { $0.teamID == teamID }
            .sorted { ($0.number ?? Int.max) < ($1.number ?? Int.max) }
    }

    private func playerLabel(_ player: Player) -> String {
        let name = (player.name?.isEmpty == false) ? player.name! : "名前未設定"
        return player.number.map { "#\($0) \(name)" } ?? name
    }

    private func teamName(_ id: UUID) -> String {
        teams.first { $0.id == id }?.name ?? "チーム"
    }

    private func setTeam(_ row: Binding<ScoreRow>, isHome: Bool) {
        // チームを変えたら、他チームの選手が付いたままにならないよう選手を外す
        if row.wrappedValue.isHome != isHome {
            row.wrappedValue.isHome = isHome
            row.wrappedValue.playerID = nil
        }
    }

    // MARK: - Load & Save

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        // 既存の「成功した得点」を行に読み込む(失敗キック等はここでは触らない)。
        // HOME/AWAY のどちらかに紐づく得点だけを扱う(サマリーの集計と一致させる)。
        rows = loadableSuccessEvents
            .sorted { ($0.half, $0.seconds) < ($1.half, $1.seconds) }
            .compactMap { event in
                guard let category = ScoringCategory(rawValue: event.category) else { return nil }
                return ScoreRow(
                    id: event.id,
                    isHome: event.teamID == match.homeTeamID,
                    category: category,
                    half: event.half,
                    minute: max(0, event.seconds / 60),
                    playerID: event.playerID,
                    existingEventID: event.id
                )
            }
    }

    // この画面が管理する対象: HOME/AWAY のどちらかに紐づく「成功した得点」だけ
    private var loadableSuccessEvents: [StatEvent] {
        matchEvents.filter {
            ScoringCategory(rawValue: $0.category) != nil
                && $0.outcome == "success"
                && ($0.teamID == match.homeTeamID || $0.teamID == match.awayTeamID)
        }
    }

    private func save() {
        let existingSuccess = loadableSuccessEvents
        let existingByID = Dictionary(uniqueKeysWithValues: existingSuccess.map { ($0.id, $0) })
        let keptIDs = Set(rows.compactMap { $0.existingEventID })

        // 画面から消された既存の得点を削除
        for event in existingSuccess where !keptIDs.contains(event.id) {
            modelContext.delete(event)
        }

        // 行を反映(既存は更新、新規は作成)
        for row in rows {
            let teamID = row.isHome ? match.homeTeamID : match.awayTeamID
            let seconds = max(0, row.minute) * 60
            if let id = row.existingEventID, let event = existingByID[id] {
                event.teamID = teamID
                event.category = row.category.rawValue
                event.playerID = row.playerID
                event.seconds = seconds
                event.half = row.half
                event.outcome = "success"
            } else {
                modelContext.insert(StatEvent(
                    matchID: match.id,
                    teamID: teamID,
                    playerID: row.playerID,
                    category: row.category.rawValue,
                    outcome: "success",
                    seconds: seconds,
                    half: row.half
                ))
            }
        }

        try? modelContext.save()
        dismiss()
    }

    private func addRow() {
        // 直前の行の続き(同じハーフ・同じ側)を初期値にして、連続入力を楽にする
        let last = rows.last
        rows.append(
            ScoreRow(
                id: UUID(),
                isHome: last?.isHome ?? true,
                category: .tryScore,
                half: last?.half ?? 0,
                minute: last.map { $0.minute } ?? 0,
                playerID: nil,
                existingEventID: nil
            )
        )
    }
}
