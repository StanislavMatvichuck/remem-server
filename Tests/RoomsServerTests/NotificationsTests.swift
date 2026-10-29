//
//  NotificationsTests.swift
//  RoomsServerTests
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

@testable import RoomsServer
import XCTVapor

final class NotificationsTests: RoomsServerTestCase {
    func test_swipe_notifiesOtherMembers() async throws {
        let alice = try await register("Alice", deviceToken: "aliceDevice")
        let bob = try await register("Bob", deviceToken: "bobDevice")
        let carol = try await register("Carol", deviceToken: "carolDevice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        _ = try await join(room.id, by: carol)

        try await swipe(room.id, by: alice)

        let deliveries = await pushNotifier.deliveries
        XCTAssertEqual(deliveries.count, 1)
        XCTAssertEqual(Set(deliveries.first?.deviceTokens ?? []), ["bobDevice", "carolDevice"])
        XCTAssertEqual(deliveries.first?.message, PushMessage(title: "Gym", body: "Alice · Pull-ups · 1", roomId: room.id))
    }

    func test_swipe_doesNotNotifyMembersWhoMutedSender() async throws {
        let alice = try await register("Alice", deviceToken: "aliceDevice")
        let bob = try await register("Bob", deviceToken: "bobDevice")
        let carol = try await register("Carol", deviceToken: "carolDevice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        _ = try await join(room.id, by: carol)

        _ = try await setNotifications(false, roomId: room.id, member: alice.id, by: bob)
        try await swipe(room.id, by: alice)

        let deliveries = await pushNotifier.deliveries
        XCTAssertEqual(deliveries.first?.deviceTokens, ["carolDevice"])
    }

    func test_swipe_everyoneMutedSender_sendsNothing() async throws {
        let alice = try await register("Alice", deviceToken: "aliceDevice")
        let bob = try await register("Bob", deviceToken: "bobDevice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)

        _ = try await setNotifications(false, roomId: room.id, member: alice.id, by: bob)
        try await swipe(room.id, by: alice)

        let deliveries = await pushNotifier.deliveries
        XCTAssertTrue(deliveries.isEmpty)
    }

    func test_swipe_membersWithoutDeviceToken_areSkipped() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)

        try await swipe(room.id, by: alice)

        let deliveries = await pushNotifier.deliveries
        XCTAssertTrue(deliveries.isEmpty)
    }

    func test_removeHappening_notifiesNobody() async throws {
        let alice = try await register("Alice", deviceToken: "aliceDevice")
        let bob = try await register("Bob", deviceToken: "bobDevice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        let happeningId = UUID()
        try await swipe(room.id, by: alice, happeningId: happeningId)

        try await removeHappening(happeningId, roomId: room.id, by: alice)

        let deliveries = await pushNotifier.deliveries
        XCTAssertEqual(deliveries.count, 1, "Only adding happening notifies")
    }

    func test_repeatedSwipe_notifiesOnce() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob", deviceToken: "bobDevice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        let happeningId = UUID()

        try await swipe(room.id, by: alice, happeningId: happeningId)
        try await swipe(room.id, by: alice, happeningId: happeningId)

        let deliveries = await pushNotifier.deliveries
        XCTAssertEqual(deliveries.count, 1)
    }

    func test_setNotifications_isReflectedForViewerOnly() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)

        let bobsView = try await setNotifications(false, roomId: room.id, member: alice.id, by: bob)
        let alicesView = try await join(room.id, by: alice)

        XCTAssertEqual(bobsView.members.first { $0.id == alice.id }?.notificationsEnabled, false)
        XCTAssertEqual(alicesView.members.allSatisfy(\.notificationsEnabled), true)
    }

    func test_setNotifications_enableAfterDisable_notifiesAgain() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob", deviceToken: "bobDevice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)

        _ = try await setNotifications(false, roomId: room.id, member: alice.id, by: bob)
        let enabled = try await setNotifications(true, roomId: room.id, member: alice.id, by: bob)
        try await swipe(room.id, by: alice)

        XCTAssertEqual(enabled.members.first { $0.id == alice.id }?.notificationsEnabled, true)
        let deliveries = await pushNotifier.deliveries
        XCTAssertEqual(deliveries.first?.deviceTokens, ["bobDevice"])
    }

    // MARK: - Device environments

    func test_swipe_routesTokensByEnvironment() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob", deviceToken: "bobDevice", environment: .sandbox)
        let carol = try await register("Carol", deviceToken: "carolDevice", environment: .production)
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        _ = try await join(room.id, by: carol)

        try await swipe(room.id, by: alice)

        let deliveries = await pushNotifier.deliveries
        XCTAssertEqual(Set(deliveries.first?.targets ?? []), [
            PushTarget(deviceToken: "bobDevice", environment: .sandbox),
            PushTarget(deviceToken: "carolDevice", environment: .production),
        ])
    }

    func test_deviceTokenWithoutEnvironment_isSandbox() async throws {
        let bob = try await register("Bob", deviceToken: "bobDevice")

        let stored = try await User.find(bob.id, on: app.db)

        XCTAssertEqual(stored?.pushTarget, PushTarget(deviceToken: "bobDevice", environment: .sandbox))
    }

    func test_unknownEnvironment_isRejected() async throws {
        let bob = try await register("Bob")

        try await app.test(.PATCH, "v1/users/me", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: bob.token)
            try req.content.encode(["deviceToken": "bobDevice", "deviceEnvironment": "staging"])
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        })
    }

    func test_tokenRejectedByAPNs_isRemoved() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob", deviceToken: "bobDevice")
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)
        _ = try await join(room.id, by: bob)
        await pushNotifier.reject(["bobDevice"])

        try await swipe(room.id, by: alice)
        try await swipe(room.id, by: alice)

        let deliveries = await pushNotifier.deliveries
        let stored = try await User.find(bob.id, on: app.db)
        XCTAssertEqual(deliveries.count, 1, "second swipe has nobody to notify")
        XCTAssertNil(stored?.deviceToken)
    }

    func test_tokenRegisteredByNewUser_isRemovedFromPreviousUser() async throws {
        let before = try await register("Bob", deviceToken: "bobDevice")

        let after = try await register("Bob", deviceToken: "bobDevice")

        let previous = try await User.find(before.id, on: app.db)
        let current = try await User.find(after.id, on: app.db)
        XCTAssertNil(previous?.deviceToken)
        XCTAssertEqual(current?.deviceToken, "bobDevice")
    }
}
