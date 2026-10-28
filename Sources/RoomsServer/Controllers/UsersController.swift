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
        try response.content.encode(RegistrationDTO(user: UserDTO(user), token: token))
        return response
    }
}

struct ProfileController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.patch("users", "me", use: update)
    }

    /// `PATCH /v1/users/me`
    @Sendable func update(req: Request) async throws -> UserDTO {
        try UpdateProfileInput.validate(content: req)
        let input = try req.content.decode(UpdateProfileInput.self)
        let user = try req.auth.require(User.self)

        if let name = input.name { user.name = name }
        if let color = input.color { user.color = color }
        if let deviceToken = input.deviceToken { user.deviceToken = deviceToken.isEmpty ? nil : deviceToken }

        try await user.save(on: req.db)
        return try UserDTO(user)
    }
}
