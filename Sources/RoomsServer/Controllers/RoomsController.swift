//
//  RoomsController.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Fluent
import Vapor

struct RoomsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let rooms = routes.grouped("rooms")
        rooms.get(use: index)
        rooms.post(use: create)

        rooms.group(":roomId") { room in
            room.get(use: show)
            room.post("members", use: join)
            room.post("happenings", use: addHappening)
            room.put("members", ":userId", "notifications", use: setNotifications)
        }
    }

    /// `GET /v1/rooms` rooms of authenticated user
    @Sendable func index(req: Request) async throws -> [RoomDTO] {
        let user = try req.auth.require(User.self)
        let memberships = try await Membership.query(on: req.db)
            .filter(\.$user.$id == user.requireID())
            .with(\.$room)
            .sort(\.$joinedAt)
            .all()

        var rooms = [RoomDTO]()
        for membership in memberships {
            rooms.append(try await RoomPresenter(req).dto(membership.room, viewer: user))
        }
        return rooms
    }

    /// `POST /v1/rooms` creator becomes the first member
    @Sendable func create(req: Request) async throws -> Response {
        try CreateRoomInput.validate(content: req)
        let input = try req.content.decode(CreateRoomInput.self)
        let user = try req.auth.require(User.self)
        let room = Room(name: input.name, eventName: input.eventName, ownerId: try user.requireID())

        try await req.db.transaction { db in
            try await room.save(on: db)
            try await Membership(roomId: room.requireID(), userId: user.requireID()).save(on: db)
        }

        let response = Response(status: .created)
        try response.content.encode(try await RoomPresenter(req).dto(room, viewer: user))
        return response
    }

    /// `GET /v1/rooms/:roomId` members only
    @Sendable func show(req: Request) async throws -> RoomDTO {
        let user = try req.auth.require(User.self)
        let room = try await findRoom(req)
        try await requireMembership(room, user, on: req.db)
        return try await RoomPresenter(req).dto(room, viewer: user)
    }

    /// `POST /v1/rooms/:roomId/members` joins authenticated user, repeated calls are ignored
    @Sendable func join(req: Request) async throws -> RoomDTO {
        let user = try req.auth.require(User.self)
        let room = try await findRoom(req)

        if try await membership(room, user, on: req.db) == nil {
            try await Membership(roomId: room.requireID(), userId: user.requireID()).save(on: req.db)
        }

        return try await RoomPresenter(req).dto(room, viewer: user)
    }

    /// `POST /v1/rooms/:roomId/happenings` records a swipe and notifies members
    @Sendable func addHappening(req: Request) async throws -> RoomDTO {
        let input = try req.content.decode(HappeningInput.self)
        let sender = try req.auth.require(User.self)
        let room = try await findRoom(req)
        let roomId = try room.requireID()
        let senderId = try sender.requireID()
        try await requireMembership(room, sender, on: req.db)

        let alreadyRecorded = try await RoomHappening.query(on: req.db)
            .filter(\.$room.$id == roomId)
            .filter(\.$user.$id == senderId)
            .filter(\.$happeningId == input.id)
            .first() != nil

        if !alreadyRecorded {
            try await RoomHappening(
                roomId: roomId,
                userId: senderId,
                happeningId: input.id,
                dateCreated: input.dateCreated
            ).save(on: req.db)
        }

        let dto = try await RoomPresenter(req).dto(room, viewer: sender)

        if !alreadyRecorded {
            let count = dto.members.first { $0.id == senderId }?.happeningsCount ?? 0
            await notifyMembers(req, room: room, sender: sender, count: count)
        }

        return dto
    }

    /// `PUT /v1/rooms/:roomId/members/:userId/notifications` mutes or unmutes a member for authenticated user
    @Sendable func setNotifications(req: Request) async throws -> RoomDTO {
        let input = try req.content.decode(NotificationsInput.self)
        let receiver = try req.auth.require(User.self)
        let room = try await findRoom(req)
        let roomId = try room.requireID()
        let receiverId = try receiver.requireID()
        guard let senderId = req.parameters.get("userId", as: UUID.self) else { throw Abort(.badRequest) }
        try await requireMembership(room, receiver, on: req.db)

        let existingMute = try await NotificationMute.query(on: req.db)
            .filter(\.$room.$id == roomId)
            .filter(\.$receiver.$id == receiverId)
            .filter(\.$sender.$id == senderId)
            .first()

        switch (input.enabled, existingMute) {
        case (true, .some(let mute)): try await mute.delete(on: req.db)
        case (false, .none): try await NotificationMute(roomId: roomId, receiverId: receiverId, senderId: senderId).save(on: req.db)
        default: break
        }

        return try await RoomPresenter(req).dto(room, viewer: receiver)
    }

    // MARK: - Private

    private func findRoom(_ req: Request) async throws -> Room {
        guard let roomId = req.parameters.get("roomId", as: UUID.self),
              let room = try await Room.find(roomId, on: req.db)
        else {
            throw Abort(.notFound)
        }
        return room
    }

    private func membership(_ room: Room, _ user: User, on db: any Database) async throws -> Membership? {
        try await Membership.query(on: db)
            .filter(\.$room.$id == room.requireID())
            .filter(\.$user.$id == user.requireID())
            .first()
    }

    /// Not found instead of forbidden to not reveal room existence
    private func requireMembership(_ room: Room, _ user: User, on db: any Database) async throws {
        guard try await membership(room, user, on: db) != nil else { throw Abort(.notFound) }
    }

    private func notifyMembers(_ req: Request, room: Room, sender: User, count: Int) async {
        do {
            let roomId = try room.requireID()
            let senderId = try sender.requireID()

            let mutedBy = Set(try await NotificationMute.query(on: req.db)
                .filter(\.$room.$id == roomId)
                .filter(\.$sender.$id == senderId)
                .all()
                .map { $0.$receiver.id })

            let deviceTokens = try await Membership.query(on: req.db)
                .filter(\.$room.$id == roomId)
                .filter(\.$user.$id != senderId)
                .with(\.$user)
                .all()
                .filter { !mutedBy.contains($0.$user.id) }
                .compactMap { $0.user.deviceToken }

            guard !deviceTokens.isEmpty else { return }

            await req.application.pushNotifier.send(
                PushMessage(
                    title: room.name,
                    body: "\(sender.name) · \(room.eventName) · \(count)",
                    roomId: roomId
                ),
                to: deviceTokens
            )
        } catch {
            req.logger.warning("unable to notify room members: \(String(reflecting: error))")
        }
    }
}

struct RoomPresenter {
    private let db: any Database
    private let settings: Settings

    init(_ req: Request) {
        self.db = req.db
        self.settings = req.application.settings
    }

    func dto(_ room: Room, viewer: User) async throws -> RoomDTO {
        let roomId = try room.requireID()
        let viewerId = try viewer.requireID()

        let memberships = try await Membership.query(on: db)
            .filter(\.$room.$id == roomId)
            .with(\.$user)
            .sort(\.$joinedAt)
            .all()

        let muted = Set(try await NotificationMute.query(on: db)
            .filter(\.$room.$id == roomId)
            .filter(\.$receiver.$id == viewerId)
            .all()
            .map { $0.$sender.id })

        var members = [MemberDTO]()

        for membership in memberships {
            let user = membership.user
            let userId = try user.requireID()
            let happenings = { RoomHappening.query(on: db).filter(\.$room.$id == roomId).filter(\.$user.$id == userId) }

            members.append(MemberDTO(
                id: userId,
                name: user.name,
                color: user.color,
                happeningsCount: try await happenings().count(),
                lastHappeningDate: try await happenings().max(\.$dateCreated),
                notificationsEnabled: !muted.contains(userId),
                isCurrentUser: userId == viewerId
            ))
        }

        return RoomDTO(
            id: roomId,
            name: room.name,
            eventName: room.eventName,
            link: settings.joinLink(roomId: roomId),
            members: members
        )
    }
}
