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

    if settings.autoMigrate || app.environment == .testing {
        try await app.autoMigrate()
    }

    ContentConfiguration.global.use(encoder: JSONEncoder.rooms, for: .json)
    ContentConfiguration.global.use(decoder: JSONDecoder.rooms, for: .json)

    try routes(app)
}

private func configureDatabase(_ app: Application, settings: Settings) throws {
    if app.environment == .testing {
        app.databases.use(.sqlite(.memory), as: .sqlite)
    } else if let databaseURL = settings.databaseURL {
        app.databases.use(.postgres(configuration: try SQLPostgresConfiguration(url: databaseURL)), as: .psql)
    } else {
        app.logger.warning("DATABASE_URL is not set, using local SQLite file")
        app.databases.use(.sqlite(.file("rooms.sqlite")), as: .sqlite)
    }
}

private func configureNotifications(_ app: Application, settings: Settings) async throws {
    guard let apns = settings.apns, app.environment != .testing else {
        app.pushNotifier = LoggingPushNotifier(logger: app.logger)
        return
    }

    let configuration = APNSClientConfiguration(
        authenticationMethod: .jwt(
            privateKey: try .loadFrom(string: apns.privateKey),
            keyIdentifier: apns.keyId,
            teamIdentifier: apns.teamId
        ),
        environment: apns.production ? .production : .development
    )

    app.apns.containers.use(
        configuration,
        eventLoopGroupProvider: .shared(app.eventLoopGroup),
        responseDecoder: JSONDecoder(),
        requestEncoder: JSONEncoder(),
        as: .default
    )

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
