//
//  SettingsView.swift
//  Rugby AS
//
//  設定画面。V1で持つのは「デフォルト自チーム名」の1項目だけ。
//  値は端末設定(UserDefaults)に保存し、試合をつくる画面が参照する。
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTeamName") private var defaultTeamName = ""

    var body: some View {
        Form {
            Section {
                TextField("例: ○○大学", text: $defaultTeamName)
            } header: {
                Text("デフォルト自チーム名")
            } footer: {
                Text("試合をつくる画面のホームチームに、この名前が最初から入ります。")
            }

            Section {
                Label(
                    "大事な大会の後は、端末ごとiCloudバックアップをおすすめします。",
                    systemImage: "icloud"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
