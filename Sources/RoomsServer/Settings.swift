//
//  Settings.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Vapor

/// Values read from environment variables. Railway injects `PORT` and `RAILWAY_PUBLIC_DOMAIN` automatically,
/// `DATABASE_URL` comes from a Postgres service reference variable.
struct Settings: Sendable {
    struct APNS: Sendable {
        let keyId: String
        let teamId: String
        let privateKey: String
        let topic: String
        let production: Bool
    }

    let port: Int
    let publicURL: String
    let appURLScheme: String
    let databaseURL: String?
    let autoMigrate: Bool
    let apns: APNS?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        port = environment["PORT"].flatMap(Int.init) ?? 8080

        if let url = environment["PUBLIC_URL"], !url.isEmpty {
            publicURL = url.trimmingSuffix("/")
        } else if let domain = environment["RAILWAY_PUBLIC_DOMAIN"], !domain.isEmpty {
            publicURL = "https://\(domain)"
        } else {
            publicURL = "http://localhost:\(port)"
        }

        appURLScheme = environment["APP_URL_SCHEME"] ?? "remem"
        databaseURL = environment["DATABASE_URL"].flatMap { $0.isEmpty ? nil : $0 }
        autoMigrate = environment["AUTO_MIGRATE"].map { $0 != "false" } ?? true

        if let keyId = environment["APNS_KEY_ID"],
           let teamId = environment["APNS_TEAM_ID"],
           let privateKey = environment["APNS_PRIVATE_KEY"],
           !keyId.isEmpty, !teamId.isEmpty, !privateKey.isEmpty
        {
            apns = APNS(
                keyId: keyId,
                teamId: teamId,
                /// Railway variables are single line, so `\n` sequences are accepted in place of line breaks
                privateKey: privateKey.replacingOccurrences(of: "\\n", with: "\n"),
                topic: environment["APNS_TOPIC"] ?? "io.remem",
                production: environment["APNS_ENVIRONMENT"] == "production"
            )
        } else {
            apns = nil
        }
    }

    func joinLink(roomId: UUID) -> String { "\(publicURL)/join/\(roomId.uuidString)" }
    func appJoinURL(roomId: UUID) -> String { "\(appURLScheme)://rooms/join/\(roomId.uuidString)" }
}

extension Application {
    private struct SettingsKey: StorageKey { typealias Value = Settings }

    var settings: Settings {
        get { storage[SettingsKey.self] ?? Settings() }
        set { storage[SettingsKey.self] = newValue }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
