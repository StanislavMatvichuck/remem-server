//
//  AvatarsController.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 28.10.2026.
//

import Fluent
import Vapor

/// `GET /avatars/:userId` is public so the app loads photos like any image.
/// Links contain avatar version, so responses are cached forever and a new upload gets a new link.
struct AvatarsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("avatars", ":userId", use: avatar)
    }

    @Sendable func avatar(req: Request) async throws -> Response {
        guard let userId = req.parameters.get("userId", as: UUID.self),
              let avatar = try await Avatar.query(on: req.db).filter(\.$user.$id == userId).first()
        else { throw Abort(.notFound) }

        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentType, value: avatar.contentType)
        headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=31536000, immutable")
        return Response(status: .ok, headers: headers, body: .init(data: avatar.data))
    }
}
