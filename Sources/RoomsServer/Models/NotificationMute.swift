//
//  NotificationMute.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
import Vapor

/// Presence of a record means `receiver` turned notifications off for `sender` within `room`
final class NotificationMute: Model, @unchecked Sendable {
    static let schema = "notification_mutes"

    @ID(key: .id) var id: UUID?
    @Parent(key: "room_id") var room: Room
    @Parent(key: "receiver_id") var receiver: User
    @Parent(key: "sender_id") var sender: User

    init() {}

    init(roomId: UUID, receiverId: UUID, senderId: UUID) {
        self.$room.id = roomId
        self.$receiver.id = receiverId
        self.$sender.id = senderId
    }
}

struct CreateNotificationMute: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(NotificationMute.schema)
            .id()
            .field("room_id", .uuid, .required, .references(Room.schema, "id", onDelete: .cascade))
            .field("receiver_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("sender_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .unique(on: "room_id", "receiver_id", "sender_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(NotificationMute.schema).delete()
    }
}
