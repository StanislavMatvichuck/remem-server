//
//  Room.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
import Vapor

final class Room: Model, @unchecked Sendable {
    static let schema = "rooms"

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Field(key: "event_name") var eventName: String
    @Parent(key: "owner_id") var owner: User
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, name: String, eventName: String, ownerId: UUID) {
        self.id = id
        self.name = name
        self.eventName = eventName
        self.$owner.id = ownerId
    }
}

struct CreateRoom: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Room.schema)
            .id()
            .field("name", .string, .required)
            .field("event_name", .string, .required)
            .field("owner_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Room.schema).delete()
    }
}
