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
        }
        .modelContainer(for: [
            Team.self,
            Player.self,
            Tournament.self,
            Match.self,
            StatEvent.self,
            Substitution.self
        ])
    }
}
