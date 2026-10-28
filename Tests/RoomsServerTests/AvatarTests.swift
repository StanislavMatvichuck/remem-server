//
//  AvatarTests.swift
//  RoomsServerTests
//
//  Created by Stanislav Matvichuck on 28.10.2026.
//

import Fluent
@testable import RoomsServer
import XCTVapor

final class AvatarTests: RoomsServerTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x01, count: 64))
    private let otherJpeg = Data([0xFF, 0xD8, 0xFF, 0xE1] + Array(repeating: 0x02, count: 64))
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0x03, count: 64))

    func test_upload_returnsAvatarURL() async throws {
        let alice = try await register("Alice")

        let (status, user) = try await upload(jpeg, by: alice)

        XCTAssertEqual(status, .ok)
        XCTAssertEqual(user?.avatarURL, "https://rooms.remem.test/avatars/\(alice.id.uuidString)?v=1")
    }

    func test_avatar_isServedWithContentTypeAndLongCaching() async throws {
        let alice = try await register("Alice")
        _ = try await upload(png, by: alice)

        try await app.test(.GET, "avatars/\(alice.id.uuidString)", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.headers.contentType, .png)
            XCTAssertEqual(res.headers.first(name: .cacheControl), "public, max-age=31536000, immutable")
            XCTAssertEqual(Data(res.body.readableBytesView), self.png)
        })
    }

    func test_uploadAgain_replacesAvatarAndChangesURL() async throws {
        let alice = try await register("Alice")
        _ = try await upload(jpeg, by: alice)

        let (_, user) = try await upload(otherJpeg, by: alice)

        XCTAssertEqual(user?.avatarURL, "https://rooms.remem.test/avatars/\(alice.id.uuidString)?v=2")
        let stored = try await Avatar.query(on: app.db).all()
        XCTAssertEqual(stored.map(\.data), [otherJpeg])
    }

    func test_roomMembers_haveAvatarURL() async throws {
        let alice = try await register("Alice")
        let bob = try await register("Bob")
        _ = try await upload(jpeg, by: alice)
        let room = try await createRoom("Gym", eventName: "Pull-ups", by: alice)

        let joined = try await join(room.id, by: bob)

        XCTAssertEqual(joined.members.first { $0.id == alice.id }?.avatarURL, "https://rooms.remem.test/avatars/\(alice.id.uuidString)?v=1")
        XCTAssertNil(joined.members.first { $0.id == bob.id }?.avatarURL, "members without photo show initials")
    }

    func test_upload_nineMegabytes_isAccepted() async throws {
        let alice = try await register("Alice")

        let (status, _) = try await upload(jpeg + Data(count: 9 * 1024 * 1024), by: alice)

        XCTAssertEqual(status, .ok)
    }

    func test_upload_notAnImage_isRejected() async throws {
        let alice = try await register("Alice")

        let (status, _) = try await upload(Data("hello".utf8), by: alice)

        XCTAssertEqual(status, .unsupportedMediaType)
    }

    func test_upload_tooLarge_isRejected() async throws {
        let alice = try await register("Alice")

        let (status, _) = try await upload(jpeg + Data(count: AvatarImage.maxBytes), by: alice)

        XCTAssertEqual(status, .payloadTooLarge)
    }

    func test_upload_requiresToken() async throws {
        try await app.test(.PUT, "v1/users/me/avatar", beforeRequest: { req async throws in
            req.headers.contentType = .jpeg
            req.body = ByteBuffer(bytes: Array(self.jpeg))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    func test_avatarOfUserWithoutPhoto_notFound() async throws {
        let alice = try await register("Alice")

        try await app.test(.GET, "avatars/\(alice.id.uuidString)", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
    }

    // MARK: - Private

    private func upload(_ data: Data, by user: RegisteredUser) async throws -> (HTTPStatus, UserDTO?) {
        var result: (HTTPStatus, UserDTO?)!

        try await app.test(.PUT, "v1/users/me/avatar", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: user.token)
            req.headers.contentType = .jpeg
            req.body = ByteBuffer(bytes: Array(data))
        }, afterResponse: { res async throws in
            result = (res.status, res.status == .ok ? try res.content.decode(UserDTO.self) : nil)
        })

        return result
    }
}
