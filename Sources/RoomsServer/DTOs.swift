//
//  DTOs.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Vapor

/// Contract shared with the Remem client, mirrored by `DataLayer/Rooms/RoomsDTO.swift`

struct UserDTO: Content, Equatable {
    let id: UUID
    let name: String
    let color: String
    let avatarURL: String?
}

struct RegistrationDTO: Content {
    let user: UserDTO
    let token: String
}

struct MemberDTO: Content, Equatable {
    let id: UUID
    let name: String
    let color: String
    let happeningsCount: Int
    let lastHappeningDate: Date?
    /// Whether requesting user receives notifications when this member swipes
    let notificationsEnabled: Bool
    let isCurrentUser: Bool
    /// Absent until member uploads a photo
    let avatarURL: String?
}

struct RoomDTO: Content, Equatable {
    let id: UUID
    let name: String
    let eventName: String
    let link: String
    let members: [MemberDTO]
}

// MARK: - Inputs

struct RegisterInput: Content, Validatable {
    let name: String
    let color: String

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(...Limits.name))
        validations.add("color", as: String.self, is: .pattern(Limits.colorPattern))
    }
}

struct UpdateProfileInput: Content, Validatable {
    let name: String?
    let color: String?
    let deviceToken: String?
    /// `sandbox` when omitted
    let deviceEnvironment: PushEnvironment?

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: .count(...Limits.name), required: false)
        validations.add("color", as: String.self, is: .pattern(Limits.colorPattern), required: false)
        validations.add("deviceToken", as: String.self, is: .count(...200) && .characterSet(.alphanumerics), required: false)
        validations.add("deviceEnvironment", as: String.self, is: .in(PushEnvironment.allCases.map(\.rawValue)), required: false)
    }
}

struct CreateRoomInput: Content, Validatable {
    let name: String
    let eventName: String

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: !.empty && .count(...Limits.name))
        validations.add("eventName", as: String.self, is: !.empty && .count(...Limits.name))
    }
}

struct HappeningInput: Content {
    let id: UUID
    let dateCreated: Date
}

struct HappeningDTO: Content, Equatable {
    let id: UUID
    let dateCreated: Date
}

/// Room event of a single member
struct EventDTO: Content, Equatable {
    let name: String
    let dateCreated: Date
    let happenings: [HappeningDTO]
}

struct MemberEventDTO: Content, Equatable {
    let memberId: UUID
    let event: EventDTO
}

struct NotificationsInput: Content {
    let enabled: Bool
}

enum Limits {
    static let name = 60
    static let colorPattern = "^#[0-9A-Fa-f]{6}$"
}

extension UserDTO {
    init(_ user: User, settings: Settings) throws {
        let id = try user.requireID()
        self.init(
            id: id,
            name: user.name,
            color: user.color,
            avatarURL: settings.avatarURL(userId: id, version: user.avatarVersion)
        )
    }
}
