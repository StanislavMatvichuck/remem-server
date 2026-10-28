//
//  JoinPageController.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
import Vapor

/// Shared room links are web links so messengers render them as tappable.
/// The page forwards to the app URL scheme handled by `SceneDelegate`.
struct JoinPageController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("join", ":roomId", use: page)
    }

    @Sendable func page(req: Request) async throws -> Response {
        guard let roomId = req.parameters.get("roomId", as: UUID.self),
              try await Room.find(roomId, on: req.db) != nil
        else { throw Abort(.notFound) }

        let appURL = req.application.settings.appJoinURL(roomId: roomId)
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="refresh" content="0; url=\(appURL)">
        <title>Join room in Remem</title>
        </head>
        <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 30vh;">
        <a href="\(appURL)">Open in Remem</a>
        </body>
        </html>
        """

        var headers = HTTPHeaders()
        headers.contentType = .html
        return Response(status: .ok, headers: headers, body: .init(string: html))
    }
}
