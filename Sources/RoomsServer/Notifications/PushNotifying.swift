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

protocol PushNotifying: Sendable {
    func send(_ message: PushMessage, to deviceTokens: [String]) async
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

    func send(_ message: PushMessage, to deviceTokens: [String]) async {
        logger.info("push skipped, APNS is not configured: \(message.title) - \(message.body) to \(deviceTokens.count) devices")
    }
}

struct APNSPushNotifier: PushNotifying {
    struct Payload: Codable, Sendable { let roomId: String }

    let app: Application
    let topic: String

    func send(_ message: PushMessage, to deviceTokens: [String]) async {
        for deviceToken in deviceTokens {
            do {
                try await app.apns.client.sendAlertNotification(
                    APNSAlertNotification(
                        alert: .init(title: .raw(message.title), body: .raw(message.body)),
                        expiration: .immediately,
                        priority: .immediately,
                        topic: topic,
                        payload: Payload(roomId: message.roomId.uuidString),
                        sound: .default
                    ),
                    deviceToken: deviceToken
                )
            } catch {
                app.logger.warning("push delivery failed: \(String(reflecting: error))")
            }
        }
    }
}
