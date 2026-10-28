//
//  UsersController.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
import Vapor

struct UsersController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("users", use: register)
    }

    /// `POST /v1/users`, the only endpoint without authentication. Token is returned once.
    @Sendable func register(req: Request) async throws -> Response {
        try RegisterInput.validate(content: req)
        let input = try req.content.decode(RegisterInput.self)
        let token = Token.generate()
        let user = User(name: input.name, color: input.color, tokenHash: Token.hash(token))

        try await user.save(on: req.db)

        let response = Response(status: .created)
        try response.content.encode(RegistrationDTO(user: UserDTO(user, settings: req.application.settings), token: token))
        return response
    }
}

struct ProfileController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.patch("users", "me", use: update)
        routes.on(.PUT, "users", "me", "avatar", body: .collect(maxSize: AvatarImage.maxSize), use: uploadAvatar)
    }

    /// `PATCH /v1/users/me`
    @Sendable func update(req: Request) async throws -> UserDTO {
        try UpdateProfileInput.validate(content: req)
        let input = try req.content.decode(UpdateProfileInput.self)
        let user = try req.auth.require(User.self)

        if let name = input.name { user.name = name }
        if let color = input.color { user.color = color }

        if let deviceToken = input.deviceToken {
            let token = deviceToken.isEmpty ? nil : deviceToken
            user.deviceToken = token
            user.deviceEnvironment = token == nil ? nil : (input.deviceEnvironment ?? .sandbox).rawValue
            let userId = try user.requireID()
            req.logger.notice("device token \(token == nil ? "removed" : "registered for \(user.deviceEnvironment ?? "")") for user \(userId)")

            /// After reinstall the app registers a new user, so the same device must stop receiving pushes for the old one
            if let token {
                try await User.query(on: req.db)
                    .filter(\.$deviceToken == token)
                    .filter(\.$id != userId)
                    .set(\.$deviceToken, to: nil)
                    .set(\.$deviceEnvironment, to: nil)
                    .update()
            }
        }

        try await user.save(on: req.db)
        return try UserDTO(user, settings: req.application.settings)
    }

    /// `PUT /v1/users/me/avatar` with JPEG or PNG bytes as body
    @Sendable func uploadAvatar(req: Request) async throws -> UserDTO {
        let user = try req.auth.require(User.self)
        let userId = try user.requireID()

        guard let body = req.body.data, body.readableBytes > 0 else { throw Abort(.badRequest) }
        guard body.readableBytes <= AvatarImage.maxBytes else { throw Abort(.payloadTooLarge) }
        let data = Data(body.readableBytesView)
        guard let contentType = AvatarImage.contentType(of: data) else { throw Abort(.unsupportedMediaType) }

        try await req.db.transaction { db in
            if let avatar = try await Avatar.query(on: db).filter(\.$user.$id == userId).first() {
                avatar.data = data
                avatar.contentType = contentType.serialize()
                try await avatar.save(on: db)
            } else {
                try await Avatar(userId: userId, data: data, contentType: contentType.serialize()).create(on: db)
            }

            user.avatarVersion = (user.avatarVersion ?? 0) + 1
            try await user.save(on: db)
        }

        return try UserDTO(user, settings: req.application.settings)
    }
}
