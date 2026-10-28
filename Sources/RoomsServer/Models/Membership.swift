//
//  Membership.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
import Vapor

final class Membership: Model, @unchecked Sendable {
    static let schema = "memberships"

    @ID(key: .id) var id: UUID?
    @Parent(key: "room_id") var room: Room
    @Parent(key: "user_id") var user: User
    @Timestamp(key: "joined_at", on: .create) var joinedAt: Date?

    init() {}

    init(roomId: UUID, userId: UUID) {
        self.$room.id = roomId
        self.$user.id = userId
    }
}

struct CreateMembership: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Membership.schema)
            .id()
            .field("room_id", .uuid, .required, .references(Room.schema, "id", onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("joined_at", .datetime)
            .unique(on: "room_id", "user_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Membership.schema).delete()
    }
}
