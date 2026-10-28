//
//  UsersTests.swift
//  RoomsServerTests
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

@testable import RoomsServer
import XCTVapor

final class UsersTests: RoomsServerTestCase {
    func test_health() async throws {
        try await app.test(.GET, "health", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "ok")
        })
    }

    func test_register_returnsUserAndToken() async throws {
        try await app.test(.POST, "v1/users", beforeRequest: { req async throws in
            try req.content.encode(["name": "Alice", "color": "#34C759"])
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            let registration = try res.content.decode(RegistrationDTO.self)
            XCTAssertEqual(registration.user.name, "Alice")
            XCTAssertEqual(registration.user.color, "#34C759")
            XCTAssertFalse(registration.token.isEmpty)
        })
    }

    func test_register_invalidColor_isRejected() async throws {
        try await app.test(.POST, "v1/users", beforeRequest: { req async throws in
            try req.content.encode(["name": "Alice", "color": "orange"])
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        })
    }

    func test_tokenIsStoredHashed() async throws {
        let alice = try await register("Alice")
        let stored = try await User.find(alice.id, on: app.db)

        XCTAssertNotEqual(stored?.tokenHash, alice.token)
        XCTAssertEqual(stored?.tokenHash, Token.hash(alice.token))
    }

    func test_updateProfile_changesNameColorAndDeviceToken() async throws {
        let alice = try await register("Alice")

        try await app.test(.PATCH, "v1/users/me", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: alice.token)
            try req.content.encode(["name": "Alicia", "color": "#007AFF", "deviceToken": "abc123"])
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let user = try res.content.decode(UserDTO.self)
            XCTAssertEqual(user.name, "Alicia")
            XCTAssertEqual(user.color, "#007AFF")
        })

        let stored = try await User.find(alice.id, on: app.db)
        XCTAssertEqual(stored?.deviceToken, "abc123")
    }

    func test_protectedEndpoints_requireToken() async throws {
        try await app.test(.GET, "v1/rooms", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })

        try await app.test(.GET, "v1/rooms", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: "invalid")
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }
}
