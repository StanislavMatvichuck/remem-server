//
//  routes.swift
//  RoomsServer
//
//  Created by Stanislav Matvichuck on 27.10.2026.
//

import Vapor

func routes(_ app: Application) throws {
    app.get("health") { _ in "ok" }

    try app.register(collection: JoinPageController())
    try app.register(collection: AvatarsController())

    let v1 = app.grouped("v1")
    try v1.register(collection: UsersController())

    let authenticated = v1.grouped(UserBearerAuthenticator(), User.guardMiddleware())
    try authenticated.register(collection: ProfileController())
    try authenticated.register(collection: RoomsController())
}
