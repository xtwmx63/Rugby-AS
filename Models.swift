//
//  Models.swift
//  Rugby AS
//
//  Created by Codex on 2026/05/17.
//

import Foundation
import SwiftData

@Model
final class Team {
    @Attribute(.unique) var id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class Player {
    @Attribute(.unique) var id: UUID
    var teamID: UUID
    var number: Int
    var name: String?

    init(id: UUID = UUID(), teamID: UUID, number: Int, name: String? = nil) {
        self.id = id
        self.teamID = teamID
        self.number = number
        self.name = name
    }
}

@Model
final class Tournament {
    @Attribute(.unique) var id: UUID
    var officialName: String

    init(id: UUID = UUID(), officialName: String) {
        self.id = id
        self.officialName = officialName
    }
}

@Model
final class Match {
    @Attribute(.unique) var id: UUID
    var tournamentID: UUID
    var homeTeamID: UUID
    var awayTeamID: UUID
    var playedAt: Date

    init(
        id: UUID = UUID(),
        tournamentID: UUID,
        homeTeamID: UUID,
        awayTeamID: UUID,
        playedAt: Date
    ) {
        self.id = id
        self.tournamentID = tournamentID
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.playedAt = playedAt
    }
}

@Model
final class StatEvent {
    @Attribute(.unique) var id: UUID
    var matchID: UUID
    var teamID: UUID?
    var playerID: UUID?
    var category: String
    var outcome: String
    var seconds: Int
    // 0 = 前半, 1 = 後半。既存データは default 0（前半）として扱う。
    var half: Int = 0

    init(
        id: UUID = UUID(),
        matchID: UUID,
        teamID: UUID? = nil,
        playerID: UUID? = nil,
        category: String,
        outcome: String,
        seconds: Int,
        half: Int = 0
    ) {
        self.id = id
        self.matchID = matchID
        self.teamID = teamID
        self.playerID = playerID
        self.category = category
        self.outcome = outcome
        self.seconds = seconds
        self.half = half
    }
}

@Model
final class Substitution {
    @Attribute(.unique) var id: UUID
    var matchID: UUID
    var playerInID: UUID
    var playerOutID: UUID
    var minute: Int

    init(
        id: UUID = UUID(),
        matchID: UUID,
        playerInID: UUID,
        playerOutID: UUID,
        minute: Int
    ) {
        self.id = id
        self.matchID = matchID
        self.playerInID = playerInID
        self.playerOutID = playerOutID
        self.minute = minute
    }
}
