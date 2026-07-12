//
//  Rugby_ASApp.swift
//  Rugby AS
//
//  Created by 35 on 2026/05/17.
//

import SwiftUI
import SwiftData

@main
struct Rugby_ASApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // アプリはダーク前提のデザインなので全体をダーク固定にする
                // (端末がライトモードでも設定画面などが白く混ざらないように)
                .preferredColorScheme(.dark)
                .task {
                    // 取り込み済みの試合動画をiCloudバックアップの対象から外す
                    VideoStorage.excludeAllVideosFromBackup()
                }
        }
        .modelContainer(for: [
            Team.self,
            Player.self,
            Tournament.self,
            Match.self,
            StatEvent.self,
            MatchLineup.self,
            Substitution.self
        ])
    }
}
