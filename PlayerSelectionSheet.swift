//
//  PlayerSelectionSheet.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import SwiftUI

struct PlayerSelectionSheet: View {
    let players: [Player]
    let title: String
    // その試合での背番号を返す(未指定なら基本番号)。
    // ラグビーは試合ごとに背番号が変わるため、呼び出し側が差し替えられる。
    var numberFor: ((Player) -> Int)? = nil
    let onSelect: (Player?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button("選手なし") {
                    onSelect(nil)
                }

                ForEach(sortedPlayers) { player in
                    Button {
                        onSelect(player)
                    } label: {
                        HStack {
                            Text("#\(displayNumber(for: player))")
                                .font(.headline.monospacedDigit())
                                .frame(width: 48, alignment: .leading)

                            Text(player.name ?? "名前未設定")
                                .foregroundStyle(player.name == nil ? .secondary : .primary)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var sortedPlayers: [Player] {
        players.sorted { displayNumber(for: $0) < displayNumber(for: $1) }
    }

    private func displayNumber(for player: Player) -> Int {
        numberFor?(player) ?? player.number
    }
}
