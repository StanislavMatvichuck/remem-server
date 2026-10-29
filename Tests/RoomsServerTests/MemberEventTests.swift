//
//  MemberEventTests.swift
//  RoomsServerTests
//
//  Created by Stanislav Matvichuck on 29.10.2026.
//

@testable import RoomsServer
import XCTVapor

/// Each member keeps own copy of room event, other members open it read-only
final class MemberEventTests: RoomsServerTestCase {
    func test_memberEvent_hasRoomEventNameAndMemberHappeningsByDate() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        let first = UUID()
        let second = UUID()
        try await swipe(room.id, by: alice, happeningId: second, date: Date(timeIntervalSince1970: 200))
        try await swipe(room.id, by: alice, happeningId: first, date: Date(timeIntervalSince1970: 100))
        try await swipe(room.id, by: bob)

        let event = try await memberEvent(room.id, member: alice.id, by: bob)

        XCTAssertEqual(event.name, "Pull-ups")
        XCTAssertEqual(event.happenings, [
            HappeningDTO(id: first, dateCreated: Date(timeIntervalSince1970: 100)),
            HappeningDTO(id: second, dateCreated: Date(timeIntervalSince1970: 200)),
        ])
    }

    func test_memberEvent_createdWhenMemberJoined() async throws {
        let alice = try await register("Alice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        let event = try await memberEvent(room.id, member: alice.id, by: alice)

        XCTAssertEqual(event.dateCreated.timeIntervalSinceNow, 0, accuracy: 60)
    }

    func test_memberEvent_viewerNotMember_notFound() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        try await app.test(.GET, "v1/rooms/\(room.id)/members/\(alice.id)/event", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: bob.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    func test_memberEvent_userNotMember_notFound() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        try await app.test(.GET, "v1/rooms/\(room.id)/members/\(bob.id)/event", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: alice.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    // MARK: - Removing happenings

    func test_removeHappening_removesItFromEventAndCount() async throws {
        let alice = try await register("Alice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        let kept = UUID()
        let removed = UUID()
        try await swipe(room.id, by: alice, happeningId: kept)
        try await swipe(room.id, by: alice, happeningId: removed)

        let updated = try await removeHappening(removed, roomId: room.id, by: alice)

        XCTAssertEqual(updated.members.first?.happeningsCount, 1)
        let event = try await memberEvent(room.id, member: alice.id, by: alice)
        XCTAssertEqual(event.happenings.map(\.id), [kept])
    }

    func test_removeHappening_ofOtherMember_keepsIt() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        let happeningId = UUID()
        try await swipe(room.id, by: alice, happeningId: happeningId)

        try await removeHappening(happeningId, roomId: room.id, by: bob)

        let event = try await memberEvent(room.id, member: alice.id, by: alice)
        XCTAssertEqual(event.happenings.map(\.id), [happeningId])
    }

    func test_removeHappening_unknownId_keepsCount() async throws {
        let alice = try await register("Alice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        try await swipe(room.id, by: alice)

        let updated = try await removeHappening(UUID(), roomId: room.id, by: alice)

        XCTAssertEqual(updated.members.first?.happeningsCount, 1)
    }

    func test_removeHappening_notMember_notFound() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        try await app.test(.DELETE, "v1/rooms/\(room.id)/happenings/\(UUID())", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: bob.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }
}
