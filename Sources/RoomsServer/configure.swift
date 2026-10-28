//
//  configure.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import APNS
import Fluent
import FluentPostgresDriver
import FluentSQLiteDriver
import Vapor
import VaporAPNS

func configure(_ app: Application, settings: Settings = Settings()) async throws {
    app.settings = settings
    app.http.server.configuration.port = settings.port

    try configureDatabase(app, settings: settings)
    try await configureNotifications(app, settings: settings)

    app.migrations.add(CreateUser())
    app.migrations.add(CreateRoom())
    app.migrations.add(CreateMembership())
    app.migrations.add(CreateRoomHappening())
    app.migrations.add(CreateNotificationMute())
    app.migrations.add(AddUserDeviceEnvironment())

    if settings.autoMigrate || app.environment == .testing {
        try await app.autoMigrate()
        app.logger.notice("Database migrations are up to date")
    }

    ContentConfiguration.global.use(encoder: JSONEncoder.rooms, for: .json)
    ContentConfiguration.global.use(decoder: JSONDecoder.rooms, for: .json)

    try routes(app)
}

private func configureDatabase(_ app: Application, settings: Settings) throws {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else if let databaseURL = settings.databaseURL {
        app.databases.use(.postgres(configuration: try postgresConfiguration(url: databaseURL)), as: .psql)
        /// Production log level is `notice`, so database is named explicitly, credentials are not logged
        app.logger.notice("Using Postgres at \(URLComponents(string: databaseURL)?.host ?? "unknown host")")
    } else {
        app.logger.warning("DATABASE_URL is not set, using local SQLite file")
        app.databases.use(.sqlite(.file("rooms.sqlite")), as: .sqlite)
    }
}

/// Railway Postgres has a self-signed certificate that fails TLS verification.
/// Its private network `*.railway.internal` is already encrypted, so TLS is disabled there unless `sslmode` is set.
func postgresConfiguration(url: String) throws -> SQLPostgresConfiguration {
    var configuration = try SQLPostgresConfiguration(url: url)
    let components = URLComponents(string: url)
    let tlsModeSpecified = components?.queryItems?.contains {
        ["tlsmode", "sslmode", "ssl", "tls"].contains($0.name.lowercased())
    } ?? false

    if !tlsModeSpecified, components?.host?.hasSuffix(".railway.internal") == true {
        configuration.coreConfiguration.tls = .disable
    }

    return configuration
}

private func configureNotifications(_ app: Application, settings: Settings) async throws {
    guard let apns = settings.apns, app.environment != .testing else {
        app.pushNotifier = LoggingPushNotifier(logger: app.logger)
        return
    }

    /// One key works for both environments, device tokens are routed by environment they were issued for
    for environment in PushEnvironment.allCases {
        let configuration = APNSClientConfiguration(
            authenticationMethod: .jwt(
                privateKey: try .loadFrom(string: apns.privateKey),
                keyIdentifier: apns.keyId,
                teamIdentifier: apns.teamId
            ),
            environment: environment == .production ? .production : .development
        )

        app.apns.containers.use(
            configuration,
            eventLoopGroupProvider: .shared(app.eventLoopGroup),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: environment.containerId
        )
    }

    app.logger.notice("APNS is configured for topic \(apns.topic)")
    app.pushNotifier = APNSPushNotifier(app: app, topic: apns.topic)
}

extension JSONEncoder {
    static var rooms: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var rooms: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
