//
//  RoomsTests.swift
//  RoomsServerTests
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
@testable import RoomsServer
import XCTVapor

final class RoomsTests: RoomsServerTestCase {
    func test_createRoom_creatorIsTheOnlyMember() async throws {
        let alice = try await register("Alice")

        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        XCTAssertEqual(room.name, "Gym")
        XCTAssertEqual(room.eventName, "Pull-ups")
        XCTAssertEqual(room.members.map(\.name), ["Alice"])
        XCTAssertEqual(room.members.first?.isCurrentUser, true)
        XCTAssertEqual(room.members.first?.happeningsCount, 0)
    }

    func test_createRoom_providesJoinLink() async throws {
        let alice = try await register("Alice")

        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        XCTAssertEqual(room.link, "https://rooms.remem.test/join/\(room.id.uuidString)")
    }

    func test_createRoom_emptyEventName_isRejected() async throws {
        let alice = try await register("Alice")

        try await app.test(.POST, "v1/rooms", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: alice.token)
            try req.content.encode(["name": "Gym", "eventName": ""])
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        })
    }

    func test_join_addsMember() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let created = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        let joined = try await join(created.id, by: bob)

        XCTAssertEqual(joined.members.map(\.name), ["Alice", "Bob"])
        XCTAssertEqual(joined.members.first { $0.isCurrentUser }?.name, "Bob")
    }

    func test_members_sortedByTotalAmount() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let carol = try await register("Carol")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        _ = try await join(room.id, by: carol)
        try await swipe(room.id, by: carol)
        try await swipe(room.id, by: bob)

        let updated = try await swipe(room.id, by: bob)

        XCTAssertEqual(updated.members.map(\.name), ["Bob", "Carol", "Alice"])
    }

    func test_members_equalTotal_keepJoiningOrder() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        try await swipe(room.id, by: bob)

        let updated = try await swipe(room.id, by: alice)

        XCTAssertEqual(updated.members.map(\.name), ["Alice", "Bob"])
    }

    func test_members_removedHappening_movesMemberDown() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        let happeningId = UUID()
        let swiped = try await swipe(room.id, by: bob, happeningId: happeningId)

        let updated = try await removeHappening(happeningId, roomId: room.id, by: bob)

        XCTAssertEqual(swiped.members.map(\.name), ["Bob", "Alice"])
        XCTAssertEqual(updated.members.map(\.name), ["Alice", "Bob"])
    }

    func test_join_twice_keepsSingleMembership() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let created = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        _ = try await join(created.id, by: bob)
        let joinedAgain = try await join(created.id, by: bob)

        XCTAssertEqual(joinedAgain.members.count, 2)
    }

    func test_join_unknownRoom_notFound() async throws {
        let bob = try await register("Bob")

        try await app.test(.POST, "v1/rooms/\(UUID())/members", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: bob.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    func test_index_listsOnlyRoomsOfUser() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        _ = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await createRoom("Books", eventName: "Pages", by: bob)

        try await app.test(.GET, "v1/rooms", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: alice.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let rooms = try res.content.decode([RoomDTO].self)
            XCTAssertEqual(rooms.map(\.name), ["Gym"])
        })
    }

    func test_show_notMember_notFound() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        try await app.test(.GET, "v1/rooms/\(room.id)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: bob.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    func test_addHappening_increasesSenderCount() async throws {
        let alice = try await register("Alice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        let updated = try await swipe(room.id, by: alice)

        XCTAssertEqual(updated.members.first?.happeningsCount, 1)
        XCTAssertEqual(updated.members.first?.lastHappeningDate, Date(timeIntervalSince1970: 0))
    }

    func test_addHappening_sameIdTwice_countedOnce() async throws {
        let alice = try await register("Alice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        let happeningId = UUID()

        try await swipe(room.id, by: alice, happeningId: happeningId)
        let updated = try await swipe(room.id, by: alice, happeningId: happeningId)

        XCTAssertEqual(updated.members.first?.happeningsCount, 1)
    }

    func test_addHappening_notMember_notFound() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        try await app.test(.POST, "v1/rooms/\(room.id)/happenings", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: bob.token)
            try req.content.encode(HappeningInput(id: UUID(), dateCreated: .now))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    func test_joinPage_forwardsToAppScheme() async throws {
        let alice = try await register("Alice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        try await app.test(.GET, "join/\(room.id.uuidString)", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.headers.contentType, .html)
            XCTAssertTrue(res.body.string.contains("remem://rooms/join/\(room.id.uuidString)"))
        })
    }

    func test_joinPage_unknownRoom_notFound() async throws {
        try await app.test(.GET, "join/\(UUID().uuidString)", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    // MARK: - Leaving

    func test_leave_removesMember() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)

        let status = try await leave(room.id, by: bob)

        XCTAssertEqual(status, .noContent)
        let alicesView = try await join(room.id, by: alice)
        XCTAssertEqual(alicesView.members.map(\.name), ["Alice"])

        try await app.test(.GET, "v1/rooms", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: bob.token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(try res.content.decode([RoomDTO].self).count, 0)
        })
    }

    func test_leave_removesLeaversSwipesAndMutes() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        try await swipe(room.id, by: bob)
        _ = try await setNotifications(false, roomId: room.id, member: bob.id, by: alice)

        _ = try await leave(room.id, by: bob)

        let bobsSwipes = try await RoomHappening.query(on: app.db).filter(\.$user.$id == bob.id).count()
        let mutes = try await NotificationMute.query(on: app.db).count()
        XCTAssertEqual(bobsSwipes, 0)
        XCTAssertEqual(mutes, 0)

        let rejoined = try await join(room.id, by: bob)
        XCTAssertEqual(rejoined.members.first { $0.isCurrentUser }?.happeningsCount, 0)
    }

    func test_leave_lastMember_deletesRoom() async throws {
        let alice = try await register("Alice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        try await swipe(room.id, by: alice)

        _ = try await leave(room.id, by: alice)

        let storedRoom = try await Room.find(room.id, on: app.db)
        let swipes = try await RoomHappening.query(on: app.db).count()
        let memberships = try await Membership.query(on: app.db).count()
        XCTAssertNil(storedRoom)
        XCTAssertEqual(swipes, 0)
        XCTAssertEqual(memberships, 0)

        try await app.test(.GET, "join/\(room.id.uuidString)", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound, "link of removed room does not work")
        })
    }

    func test_leave_notMember_notFound() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        let status = try await leave(room.id, by: bob)

        XCTAssertEqual(status, .notFound)
        let stored = try await Room.find(room.id, on: app.db)
        XCTAssertNotNil(stored)
    }
}
