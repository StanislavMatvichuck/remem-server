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
}
