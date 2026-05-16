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
    let onSelect: (Player?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button("選手なし") {
                    onSelect(nil)
                }

                ForEach(players) { player in
                    Button {
                        onSelect(player)
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
