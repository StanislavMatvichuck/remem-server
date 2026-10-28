//
//  PushNotifying.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import APNSCore
import Vapor
import VaporAPNS

struct PushMessage: Sendable, Equatable {
    let title: String
    let body: String
    let roomId: UUID
}

/// Apps run from Xcode get sandbox device tokens, TestFlight and App Store builds get production ones
enum PushEnvironment: String, Codable, Sendable, CaseIterable {
    case sandbox, production

    var containerId: APNSContainers.ID { APNSContainers.ID(string: rawValue) }
}

struct PushTarget: Sendable, Hashable {
    let deviceToken: String
    let environment: PushEnvironment
}

protocol PushNotifying: Sendable {
    /// Returns device tokens that APNs reported as no longer valid
    func send(_ message: PushMessage, to targets: [PushTarget]) async -> [String]
}

extension Application {
    private struct PushNotifierKey: StorageKey { typealias Value = any PushNotifying }

    var pushNotifier: any PushNotifying {
        get { storage[PushNotifierKey.self] ?? LoggingPushNotifier(logger: logger) }
        set { storage[PushNotifierKey.self] = newValue }
    }
}

/// Used when APNS credentials are not configured
struct LoggingPushNotifier: PushNotifying {
    let logger: Logger

    func send(_ message: PushMessage, to targets: [PushTarget]) async -> [String] {
        logger.notice("push skipped, APNS is not configured: \(message.title) - \(message.body) to \(targets.count) devices")
        return []
    }
}

struct APNSPushNotifier: PushNotifying {
    struct Payload: Codable, Sendable { let roomId: String }

    let app: Application
    let topic: String

    func send(_ message: PushMessage, to targets: [PushTarget]) async -> [String] {
        var rejected = [String]()
        var delivered = 0

        for target in targets {
            do {
                try await app.apns.client(target.environment.containerId).sendAlertNotification(
                    APNSAlertNotification(
                        alert: .init(title: .raw(message.title), body: .raw(message.body)),
                        expiration: .immediately,
                        priority: .immediately,
                        topic: topic,
                        payload: Payload(roomId: message.roomId.uuidString),
                        sound: .default
                    ),
                    deviceToken: target.deviceToken
                )
                delivered += 1
            } catch let error as APNSError where error.reason == .unregistered || error.reason == .badDeviceToken {
                rejected.append(target.deviceToken)
            } catch {
                app.logger.warning("push delivery failed: \(String(reflecting: error))")
            }
        }

        app.logger.notice("push accepted by APNs for \(delivered) of \(targets.count) devices, \(rejected.count) tokens removed")
        return rejected
    }
}
