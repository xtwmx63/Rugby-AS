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
    @State private var isShowingCreateMatchPlaceholder = false

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
                        MatchRow(match: match)
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
                        isShowingCreateMatchPlaceholder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("試合を追加")
                }
            }
            .sheet(isPresented: $isShowingCreateMatchPlaceholder) {
                NavigationStack {
                    ContentUnavailableView(
                        "試合作成はステップ4で作ります",
                        systemImage: "plus.app",
                        description: Text("今は一覧画面の入口だけを用意しています。")
                    )
                    .navigationTitle("試合をつくる")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("閉じる") {
                                isShowingCreateMatchPlaceholder = false
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MatchRow: View {
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("チーム未設定 vs チーム未設定")
                .font(.headline)

            HStack {
                Text("大会未設定")
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
