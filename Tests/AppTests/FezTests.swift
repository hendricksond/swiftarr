@testable import App
import Vapor
import XCTest
import FluentPostgreSQL
import Foundation

final class FezTests: XCTestCase {
    
    // MARK: - Configure Test Environment
    
    // set properties
    let testUsername = "grundoon"
    let testPassword = "password"
    let adminURI = "/api/v3/admin/"
    let fezURI = "/api/v3/fez/"
    let twitarrURI = "/api/v3/twitarr/"
    let userURI = "/api/v3/user/"
    let usersURI = "/api/v3/users/"
    var app: Application!
    var conn: PostgreSQLConnection!
    
    /// Reset databases, create testable app instance and connect it to database.
    override func setUp() {
        try! Application.reset()
        app = try! Application.testable()
        conn = try! app.newConnection(to: .psql).wait()
    }
    
    /// Release database connection, then shut down the app.
    override func tearDown() {
        conn.close()
        try? app.syncShutdownGracefully()
        super.tearDown()
    }
    
    // MARK: - Tests
    // Note: We migrate an "admin" user first during boot, so it is always present as `.first()`.
    
    /// `GET /api/v3/fez/types`
    /// `POST /api/v3/fez/create`
    func testCreate() throws {
        // get logged in user
        let token = try app.login(username: "verified", password: testPassword, on: conn)
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // test types
        let types = try app.getResult(
            from: fezURI + "types",
            method: .GET,
            headers: headers,
            decodeTo: [String].self
        )
        XCTAssertFalse(types.isEmpty, "should be types")
        
        // test fez with times
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        var fezCreateData = FezCreateData(
            fezType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var fezData = try app.getResult(
            from: fezURI + "create",
            method: .POST,
            headers: headers,
            body: fezCreateData,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.seamonkeys[0].username == "@verified", "should be 'verified'")
        
        // test with no times
        fezCreateData.startTime = ""
        fezCreateData.endTime = ""
        fezData = try app.getResult(
            from: fezURI + "create",
            method: .POST,
            headers: headers,
            body: fezCreateData,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.startTime == "TBD", "should be 'TBD'")
        XCTAssertTrue(fezData.endTime == "TBD", "should be 'TBD'")
        
        // test with invalid times
        fezCreateData.startTime = "abc"
        fezCreateData.endTime = "def"
        let response = try app.getResponse(
            from: fezURI + "create",
            method: .POST,
            headers: headers,
            body: fezCreateData
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
    }
    
    /// `POST /api/v3/fez/ID/join`
    /// `GET /api/v3/fez/joined`
    /// `GET /api/v3/fez/owner`
    /// `POST /api/v3/fez/ID/unjoin`
    func testJoin() throws {
        // need 3 logged in users
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "moderator", password: testPassword, on: conn)
        var moderatorHeaders = HTTPHeaders()
        moderatorHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create fez
        let types = try app.getResult(
            from: fezURI + "types",
            method: .GET,
            headers: userHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let fezCreateData = FezCreateData(
            fezType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var fezData = try app.getResult(
            from: fezURI + "create",
            method: .POST,
            headers: userHeaders,
            body: fezCreateData,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.seamonkeys[0].username == "@\(testUsername)", "should be \(testUsername)")
        
        // test join fez
        fezData = try app.getResult(
            from: fezURI + "\(fezData.fezID)/join",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(fezData.seamonkeys[1].username == "@verified", "should be '@verified'")
        
        // test waitList
        fezData = try app.getResult(
            from: fezURI + "\(fezData.fezID)/join",
            method: .POST,
            headers: moderatorHeaders,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(fezData.waitingList.count == 1, "should be 1 waiting")
        XCTAssertTrue(fezData.waitingList[0].username == "@moderator", "should be '@moderator'")

        // test joined
        var joined = try app.getResult(
            from: fezURI + "joined",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [FezData].self
        )
        XCTAssertTrue(joined.count == 1, "should be 1 fez")
        var response = try app.getResponse(
            from: fezURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: fezCreateData
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        joined = try app.getResult(
            from: fezURI + "joined",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [FezData].self
        )
        XCTAssertTrue(joined.count == 2, "should be 2 fezzes")
        
        // test owner
        let whoami = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: CurrentUserData.self
        )
        var owned = try app.getResult(
            from: fezURI + "owner",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [FezData].self
        )
        XCTAssertTrue(owned.count == 1, "should be 1 fez")
        XCTAssertTrue(owned[0].ownerID == whoami.userID, "should be \(whoami.userID)")
        owned = try app.getResult(
            from: fezURI + "owner",
            method: .GET,
            headers: userHeaders,
            decodeTo: [FezData].self
        )
        XCTAssertTrue(owned.count == 1, "should be 1 fez")
        XCTAssertTrue(owned[0].ownerID == user.userID, "should be \(user.userID)")
        
        // test unjoin
        fezData = try app.getResult(
            from: fezURI + "\(fezData.fezID)/unjoin",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(fezData.seamonkeys[1].username == "@moderator", "should be '@moderator'")
        XCTAssertTrue(fezData.waitingList.isEmpty, "should be 0 waiting")
        
        
        // test block
        let verifiedInfo = try app.getResult(
            from: usersURI + "find/verified",
            method: .GET,
            headers: userHeaders,
            decodeTo: UserInfo.self
        )
        response = try app.getResponse(
            from: usersURI + "\(verifiedInfo.userID)/block",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 201, "should be 201 Created")
        response = try app.getResponse(
            from: fezURI + "\(fezData.fezID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 404, "should be 404 Not Found")
    }
    
    func testOpen() throws {
        // need 2 logged in users
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        
        // create fezzes
        let types = try app.getResult(
            from: fezURI + "types",
            method: .GET,
            headers: userHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let fezCreateData = FezCreateData(
            fezType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        let fezData1 = try app.getResult(
            from: fezURI + "create",
            method: .POST,
            headers: userHeaders,
            body: fezCreateData,
            decodeTo: FezData.self
        )
        let fezData2 = try app.getResult(
            from: fezURI + "create",
            method: .POST,
            headers: userHeaders,
            body: fezCreateData,
            decodeTo: FezData.self
        )
        
        // test open
        var open = try app.getResult(
            from: fezURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [FezData].self
        )
        XCTAssertTrue(open.count == 2, "should be 2 fezzes")
        _ = try app.getResponse(
            from: fezURI + "\(fezData1.fezID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: fezURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [FezData].self
        )
        XCTAssertTrue(open.count == 1, "should be 1 fez")
        _ = try app.getResponse(
            from: fezURI + "\(fezData2.fezID)/join",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: fezURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [FezData].self
        )
        XCTAssertTrue(open.count == 0, "should be no fez")
        _ = try app.getResponse(
            from: fezURI + "\(fezData1.fezID)/unjoin",
            method: .POST,
            headers: verifiedHeaders
        )
        open = try app.getResult(
            from: fezURI + "open",
            method: .GET,
            headers: userHeaders,
            decodeTo: [FezData].self
        )
        XCTAssertTrue(open.count == 1, "should be 1 fez")
    }
    
    func testOwnerModify() throws {
        // need 2 users
        let user = try app.createUser(username: testUsername, password: testPassword, on: conn)
        var token = try app.login(username: testUsername, password: testPassword, on: conn)
        var userHeaders = HTTPHeaders()
        userHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        token = try app.login(username: "verified", password: testPassword, on: conn)
        var verifiedHeaders = HTTPHeaders()
        verifiedHeaders.bearerAuthorization = BearerAuthorization(token: token.token)
        let whoami = try app.getResult(
            from: userURI + "whoami",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: CurrentUserData.self
        )
        
        // create fez
        let types = try app.getResult(
            from: fezURI + "types",
            method: .GET,
            headers: verifiedHeaders,
            decodeTo: [String].self
        )
        let startTime = Date().timeIntervalSince1970
        let endTime = startTime.advanced(by: 3600)
        let fezCreateData = FezCreateData(
            fezType: types[0],
            title: "A Title!",
            info: "Some info.",
            startTime: String(startTime),
            endTime: String(endTime),
            location: "Lido Pool",
            minCapacity: 0,
            maxCapacity: 2
        )
        var fezData = try app.getResult(
            from: fezURI + "create",
            method: .POST,
            headers: verifiedHeaders,
            body: fezCreateData,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.seamonkeys[0].username == "@verified", "should be '@verified'")
        
        // test add user
        fezData = try app.getResult(
            from: fezURI + "\(fezData.fezID)/user/\(user.userID)/add",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.seamonkeys.count == 2, "should be 2 seamonkeys")
        XCTAssertTrue(fezData.seamonkeys[1].username == "@\(testUsername)", "should be '@\(testUsername)'")
        
        // test can't add twice
        var response = try app.getResponse(
            from: fezURI + "\(fezData.fezID)/user/\(user.userID)/add",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        
        // test not owner
        response = try app.getResponse(
            from: fezURI + "\(fezData.fezID)/user/\(whoami.userID)/add",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")

        // test remove user
        fezData = try app.getResult(
            from: fezURI + "\(fezData.fezID)/user/\(user.userID)/remove",
            method: .POST,
            headers: verifiedHeaders,
            decodeTo: FezData.self
        )
        XCTAssertTrue(fezData.seamonkeys[1].username == "AvailableSlot", "should be 'AvailableSlot'")
        XCTAssertTrue(fezData.seamonkeys[0].username == "@verified", "should be '@verified'")
        
        // test can't remove twice
        response = try app.getResponse(
            from: fezURI + "\(fezData.fezID)/user/\(user.userID)/remove",
            method: .POST,
            headers: verifiedHeaders
        )
        XCTAssertTrue(response.http.status.code == 400, "should be 400 Bad Request")
        
        // test not owner
        response = try app.getResponse(
            from: fezURI + "\(fezData.fezID)/user/\(whoami.userID)/remove",
            method: .POST,
            headers: userHeaders
        )
        XCTAssertTrue(response.http.status.code == 403, "should be 403 Forbidden")

    }
}
