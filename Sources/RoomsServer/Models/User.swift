//
//  User.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
import Vapor

final class User: Model, Authenticatable, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Field(key: "color") var color: String
    /// SHA256 of the bearer token, raw token is returned once at registration
    @Field(key: "token_hash") var tokenHash: String
    @OptionalField(key: "device_token") var deviceToken: String?
    /// `PushEnvironment` raw value the device token was issued for
    @OptionalField(key: "device_environment") var deviceEnvironment: String?
    /// Increased on every photo upload and added to avatar link
    @OptionalField(key: "avatar_version") var avatarVersion: Int?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, name: String, color: String, tokenHash: String) {
        self.id = id
        self.name = name
        self.color = color
        self.tokenHash = tokenHash
    }
}

struct CreateUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .id()
            .field("name", .string, .required)
            .field("color", .string, .required)
            .field("token_hash", .string, .required)
            .field("device_token", .string)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema).delete()
    }
}

/// Added after first deployment, tokens without environment are treated as `sandbox`
struct AddUserDeviceEnvironment: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(User.schema)
            .field("device_environment", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema)
            .deleteField("device_environment")
            .update()
    }
}

extension User {
    var pushTarget: PushTarget? {
        guard let deviceToken else { return nil }
        return PushTarget(
            deviceToken: deviceToken,
            environment: deviceEnvironment.flatMap(PushEnvironment.init(rawValue:)) ?? .sandbox
        )
    }
}
