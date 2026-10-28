//
//  DatabaseConfigurationTests.swift
//  RoomsServerTests
//
//  Created by Stanislav Matvichuck on 28.10.2026.
//

@testable import RoomsServer
import XCTest

final class DatabaseConfigurationTests: XCTestCase {
    func test_railwayPrivateNetwork_disablesTLS() throws {
        let sut = try postgresConfiguration(url: "postgresql://postgres:secret@postgres.railway.internal:5432/railway")

        XCTAssertFalse(sut.coreConfiguration.tls.isAllowed)
    }

    func test_railwayPrivateNetwork_explicitMode_isKept() throws {
        let sut = try postgresConfiguration(url: "postgresql://postgres:secret@postgres.railway.internal:5432/railway?sslmode=require")

        XCTAssertTrue(sut.coreConfiguration.tls.isEnforced)
    }

    func test_otherHosts_preferTLS() throws {
        let sut = try postgresConfiguration(url: "postgresql://postgres:secret@db.example.com:5432/rooms")

        XCTAssertTrue(sut.coreConfiguration.tls.isAllowed)
        XCTAssertFalse(sut.coreConfiguration.tls.isEnforced)
    }

    func test_otherHosts_sslmodeDisable() throws {
        let sut = try postgresConfiguration(url: "postgresql://postgres:secret@monorail.proxy.rlwy.net:12345/railway?sslmode=disable")

        XCTAssertFalse(sut.coreConfiguration.tls.isAllowed)
    }
}
