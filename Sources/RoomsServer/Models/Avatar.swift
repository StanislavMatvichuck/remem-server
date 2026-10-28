//
//  Avatar.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 28.10.2026.
//

import Fluent
import Vapor

/// Profile photo, stored in database because Railway container files are erased on redeploy.
/// The app uploads a 512×512 JPEG of about 50 KB.
final class Avatar: Model, @unchecked Sendable {
    static let schema = "avatars"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "data") var data: Data
    @Field(key: "content_type") var contentType: String

    init() {}

    init(userId: UUID, data: Data, contentType: String) {
        self.$user.id = userId
        self.data = data
        self.contentType = contentType
    }
}

enum AvatarImage {
    static let maxBytes = 10 * 1024 * 1024
    static let maxSize = ByteCount(value: maxBytes)

    /// Detects content type by file signature, uploads of other types are rejected
    static func contentType(of data: Data) -> HTTPMediaType? {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        return nil
    }
}

struct AddAvatars: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Avatar.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, "id", onDelete: .cascade))
            .field("data", .data, .required)
            .field("content_type", .string, .required)
            .unique(on: "user_id")
            .create()

        try await database.schema(User.schema)
            .field("avatar_version", .int)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(User.schema).deleteField("avatar_version").update()
        try await database.schema(Avatar.schema).delete()
    }
}
