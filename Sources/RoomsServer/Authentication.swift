//
//  Authentication.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
import Vapor

struct UserBearerAuthenticator: AsyncBearerAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
        let user = try await User.query(on: request.db)
            .filter(\.$tokenHash == Token.hash(bearer.token))
            .first()

        if let user { request.auth.login(user) }
    }
}

enum Token {
    static func generate() -> String {
        Data([UInt8].random(count: 32)).base64EncodedString()
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
