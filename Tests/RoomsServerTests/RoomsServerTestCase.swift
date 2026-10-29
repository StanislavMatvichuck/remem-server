//
//  RoomsServerTestCase.swift
//  RoomsServerTests
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

@testable import RoomsServer
import XCTVapor

class RoomsServerTestCase: XCTestCase {
    var app: Application!
    var pushNotifier: PushNotifierSpy!

    override func setUp() async throws {
        try await super.setUp()
        app = try await Application.make(.testing)
        try await configure(app, settings: Settings(environment: ["PUBLIC_URL": "https://rooms.remem.test"]))
        pushNotifier = PushNotifierSpy()
        app.pushNotifier = pushNotifier
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
        pushNotifier = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    struct RegisteredUser {
        let id: UUID
        let token: String
    }

    func register(
        _ name: String,
        color: String = "#FF9500",
        deviceToken: String? = nil,
        environment: PushEnvironment? = nil
    ) async throws -> RegisteredUser {
        var registration: RegistrationDTO!

        try await app.test(.POST, "v1/users", beforeRequest: { req async throws in
            try req.content.encode(["name": name, "color": color])
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            registration = try res.content.decode(RegistrationDTO.self, using: JSONDecoder.rooms)
        })

        let user = RegisteredUser(id: registration.user.id, token: registration.token)

        if let deviceToken {
            try await app.test(.PATCH, "v1/users/me", beforeRequest: { req async throws in
                req.headers.bearerAuthorization = .init(token: user.token)
                var body = ["deviceToken": deviceToken]
                if let environment { body["deviceEnvironment"] = environment.rawValue }
                try req.content.encode(body)
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
            })
        }

        return user
    }

    func createRoom(_ name: String, eventName: String, by user: RegisteredUser) async throws -> RoomDTO {
        var room: RoomDTO!

        try await app.test(.POST, "v1/rooms", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: user.token)
            try req.content.encode(["name": name, "eventName": eventName])
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            room = try res.content.decode(RoomDTO.self, using: JSONDecoder.rooms)
        })

        return room
    }

    func join(_ roomId: UUID, by user: RegisteredUser) async throws -> RoomDTO {
        var room: RoomDTO!

        try await app.test(.POST, "v1/rooms/\(roomId)/members", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: user.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            room = try res.content.decode(RoomDTO.self, using: JSONDecoder.rooms)
        })

        return room
    }

    @discardableResult
    func swipe(
        _ roomId: UUID,
        by user: RegisteredUser,
        happeningId: UUID = UUID(),
        date: Date = Date(timeIntervalSince1970: 0)
    ) async throws -> RoomDTO {
        var room: RoomDTO!

        try await app.test(.POST, "v1/rooms/\(roomId)/happenings", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: user.token)
            try req.content.encode(HappeningInput(id: happeningId, dateCreated: date), using: JSONEncoder.rooms)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            room = try res.content.decode(RoomDTO.self, using: JSONDecoder.rooms)
        })

        return room
    }

    @discardableResult
    func removeHappening(_ happeningId: UUID, roomId: UUID, by user: RegisteredUser) async throws -> RoomDTO {
        var room: RoomDTO!

        try await app.test(.DELETE, "v1/rooms/\(roomId)/happenings/\(happeningId)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: user.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            room = try res.content.decode(RoomDTO.self, using: JSONDecoder.rooms)
        })

        return room
    }

    func memberEvent(_ roomId: UUID, member: UUID, by user: RegisteredUser) async throws -> EventDTO {
        var event: EventDTO!

        try await app.test(.GET, "v1/rooms/\(roomId)/members/\(member)/event", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: user.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            event = try res.content.decode(EventDTO.self, using: JSONDecoder.rooms)
        })

        return event
    }

    func leave(_ roomId: UUID, by user: RegisteredUser) async throws -> HTTPStatus {
        var status: HTTPStatus!

        try await app.test(.DELETE, "v1/rooms/\(roomId)/members/me", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: user.token)
        }, afterResponse: { res async throws in
            status = res.status
        })

        return status
    }

    func setNotifications(_ enabled: Bool, roomId: UUID, member: UUID, by user: RegisteredUser) async throws -> RoomDTO {
        var room: RoomDTO!

        try await app.test(.PUT, "v1/rooms/\(roomId)/members/\(member)/notifications", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: user.token)
            try req.content.encode(NotificationsInput(enabled: enabled))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            room = try res.content.decode(RoomDTO.self, using: JSONDecoder.rooms)
        })

        return room
    }
}

actor PushNotifierSpy: PushNotifying {
    struct Delivery: Equatable {
        let message: PushMessage
        let targets: [PushTarget]

        var deviceTokens: [String] { targets.map(\.deviceToken) }
    }

    private(set) var deliveries = [Delivery]()
    private var rejectedTokens = Set<String>()

    /// Imitates APNs answering `Unregistered` for these tokens
    func reject(_ tokens: Set<String>) { rejectedTokens = tokens }

    func send(_ message: PushMessage, to targets: [PushTarget]) async -> [String] {
        deliveries.append(Delivery(message: message, targets: targets))
        return targets.map(\.deviceToken).filter(rejectedTokens.contains)
    }
}
