// DeeplinkKitTests.swift
// DeeplinkKitTests

import XCTest
@testable import DeeplinkKit

// MARK: - DeeplinkContextTests

final class DeeplinkContextTests: XCTestCase {

    func testContextCreation() {
        let url = URL(string: "myapp://product/123")!
        let ctx = DeeplinkContext(url: url, source: .customScheme)
        XCTAssertEqual(ctx.url, url)
        XCTAssertNil(ctx.resolvedRoute)
        XCTAssertFalse(ctx.authState.isAuthenticated)
    }

    func testAuthState() {
        XCTAssertTrue(AuthState.authenticated(userID: "u1").isAuthenticated)
        XCTAssertFalse(AuthState.unauthenticated.isAuthenticated)
        XCTAssertFalse(AuthState.unknown.isAuthenticated)
        XCTAssertEqual(AuthState.authenticated(userID: "u42").userID, "u42")
    }

    func testContextMetadata() {
        let url = URL(string: "myapp://home")!
        let ctx = DeeplinkContext(
            url: url,
            source: .pushNotification(payload: ["campaign": "summer"]),
            metadata: ["badge": "3"]
        )
        XCTAssertEqual(ctx.metadata["badge"], "3")
    }

    func testOpenOptionsDefaultsAndEquality() {
        let first = DeeplinkOpenOptions()
        let second = DeeplinkOpenOptions(presentationStyle: .automatic, animated: true)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.presentationStyle, .automatic)
        XCTAssertTrue(first.animated)
    }

    func testOpenOptionsFromURL() {
        let url = URL(string: "myapp://profile/42?dk_presentation=selectTab&dk_tab=2&dk_animated=false")!
        let options = DeeplinkOpenOptions(url: url)

        XCTAssertEqual(options.presentationStyle, .selectTab(2))
        XCTAssertFalse(options.animated)
    }
}

// MARK: - StandardURLParserTests

final class StandardURLParserTests: XCTestCase {

    var parser: StandardURLParser!

    override func setUp() {
        parser = StandardURLParser(
            schemes: ["myapp", "https"],
            templates: [
                "product/:productId",
                "store/:storeId/product/:productId",
                "profile/:userId",
                "profile/:userId/settings",
                "home",
                "category/:slug"
            ]
        )
    }

    func testSimpleCustomScheme() {
        let url = URL(string: "myapp://home")!
        let result = parser.parse(url: url)
        guard case .success(let route) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(route.identifier, "home")
    }

    func testProductRoute() {
        let url = URL(string: "myapp://product/abc123")!
        let result = parser.parse(url: url)
        guard case .success(let route) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(route.pathParams["productId"], "abc123")
    }

    func testNestedRoute() {
        let url = URL(string: "myapp://store/s99/product/p42")!
        let result = parser.parse(url: url)
        guard case .success(let route) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(route.pathParams["storeId"], "s99")
        XCTAssertEqual(route.pathParams["productId"], "p42")
    }

    func testQueryParams() {
        let url = URL(string: "myapp://product/123?ref=email&tab=reviews")!
        let result = parser.parse(url: url)
        guard case .success(let route) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(route.queryParams["ref"], "email")
        XCTAssertEqual(route.queryParams["tab"], "reviews")
    }

    func testUniversalLink() {
        let url = URL(string: "https://app.example.com/profile/42")!
        let result = parser.parse(url: url)
        guard case .success(let route) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(route.pathParams["userId"], "42")
    }

    func testUnsupportedScheme() {
        let url = URL(string: "ftp://something")!
        let result = parser.parse(url: url)
        guard case .failure(let error) = result else {
            return XCTFail("Expected failure")
        }
        if case .unsupportedScheme(let scheme) = error {
            XCTAssertEqual(scheme, "ftp")
        } else {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRouteParamTypeCasting() {
        let url = URL(string: "myapp://product/999?page=3")!
        guard case .success(let route) = parser.parse(url: url) else {
            return XCTFail()
        }
        let id: String? = route.pathParam("productId")
        XCTAssertEqual(id, "999")
        let page: Int? = route.queryParam("page")
        XCTAssertEqual(page, 3)
    }
}

// MARK: - CompositeParserTests

final class CompositeParserTests: XCTestCase {

    func testFallsBackToSecondParser() {
        let first = StandardURLParser(schemes: ["scheme1"], templates: ["home"])
        let second = StandardURLParser(schemes: ["scheme2"], templates: ["dashboard"])
        let composite = CompositeParser(parsers: [first, second])

        let url = URL(string: "scheme2://dashboard")!
        let result = composite.parse(url: url)
        guard case .success(let route) = result else {
            return XCTFail("Expected success from second parser")
        }
        XCTAssertEqual(route.identifier, "dashboard")
    }

    func testNoParserMatches() {
        let parser = CompositeParser(parsers: [])
        let url = URL(string: "unknown://path")!
        guard case .failure = parser.parse(url: url) else {
            return XCTFail("Expected failure")
        }
    }
}

// MARK: - PatternMatcherTests

final class PatternMatcherTests: XCTestCase {

    func testExactMatch() {
        let route = DeeplinkRoute(identifier: "home", rawURL: URL(string: "myapp://home")!, scheme: "myapp", host: "home")
        XCTAssertTrue(PatternMatcher.matches(route: route, pattern: "home"))
    }

    func testParameterizedMatch() {
        let route = DeeplinkRoute(identifier: "product", pathParams: ["productId": "x"], rawURL: URL(string: "myapp://product/x")!, scheme: "myapp", host: "product")
        XCTAssertTrue(PatternMatcher.matches(route: route, pattern: "product/:productId"))
    }

    func testWildcard() {
        let route = DeeplinkRoute(identifier: "anything", rawURL: URL(string: "myapp://anything")!, scheme: "myapp", host: "anything")
        XCTAssertTrue(PatternMatcher.matches(route: route, pattern: "*"))
    }

    func testNoMatch() {
        let route = DeeplinkRoute(identifier: "home", rawURL: URL(string: "myapp://home")!, scheme: "myapp", host: "home")
        XCTAssertFalse(PatternMatcher.matches(route: route, pattern: "product/:id"))
    }
}

// MARK: - DeeplinkRouterTests

final class DeeplinkRouterTests: XCTestCase {

    func testHandlerRegistrationAndDispatch() async throws {
        let router = DeeplinkRouter()
        let handler = ClosureHandler(patterns: ["home"]) { _ in }
        router.register(handler)

        let route = DeeplinkRoute(identifier: "home", rawURL: URL(string: "myapp://home")!, scheme: "myapp", host: "home")
        XCTAssertTrue(router.canRoute(route))
    }

    func testPriorityOrdering() async {
        let router = DeeplinkRouter()
        let fired = LockedArray<String>()

        let low = ClosureHandler(patterns: ["item"], priority: 10, name: "low") { _ in
            fired.append("low")
        }
        let high = ClosureHandler(patterns: ["item"], priority: 100, name: "high") { _ in
            fired.append("high")
        }

        router.register(low)
        router.register(high)

        var ctx = DeeplinkContext(url: URL(string: "myapp://item")!, source: .customScheme)
        let route = DeeplinkRoute(identifier: "item", rawURL: ctx.url, scheme: "myapp", host: "item")
        ctx.resolvedRoute = route

        try? await router.dispatch(context: ctx)
        XCTAssertEqual(fired.snapshot.first, "high")
    }

    func testNoHandlerThrows() async {
        let router = DeeplinkRouter()
        var ctx = DeeplinkContext(url: URL(string: "myapp://unknown")!, source: .customScheme)
        let route = DeeplinkRoute(identifier: "unknown", rawURL: ctx.url, scheme: "myapp", host: "unknown")
        ctx.resolvedRoute = route

        do {
            try await router.dispatch(context: ctx)
            XCTFail("Expected error")
        } catch DeeplinkError.noHandlerFound {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFallbackHandler() async throws {
        let router = DeeplinkRouter()
        let handled = LockedValue(false)
        let fallback = ClosureHandler(patterns: ["*"]) { _ in handled.set(true) }
        router.registerFallback(fallback)

        var ctx = DeeplinkContext(url: URL(string: "myapp://anything")!, source: .customScheme)
        let route = DeeplinkRoute(identifier: "anything", rawURL: ctx.url, scheme: "myapp", host: "anything")
        ctx.resolvedRoute = route

        try await router.dispatch(context: ctx)
        XCTAssertTrue(handled.snapshot)
    }
}

// MARK: - MiddlewarePipelineTests

final class MiddlewarePipelineTests: XCTestCase {

    func testMiddlewareExecutionOrder() async throws {
        let order = LockedArray<String>()

        struct RecordMiddleware: DeeplinkMiddleware {
            let name: String
            let orderRef: @Sendable (String) -> Void
            var middlewareName: String { name }

            func intercept(context: DeeplinkContext, next: @Sendable (DeeplinkContext) async throws -> Void) async throws {
                orderRef(name + "-before")
                try await next(context)
                orderRef(name + "-after")
            }
        }

        let m1 = RecordMiddleware(name: "A") { order.append($0) }
        let m2 = RecordMiddleware(name: "B") { order.append($0) }

        let pipeline = MiddlewarePipeline(middleware: [m1, m2])
        let ctx = DeeplinkContext(url: URL(string: "myapp://home")!, source: .customScheme)
        try await pipeline.execute(context: ctx) { _ in order.append("terminal") }

        XCTAssertEqual(order.snapshot, ["A-before", "B-before", "terminal", "B-after", "A-after"])
    }

    func testMiddlewareCanBlock() async {
        struct BlockingMiddleware: DeeplinkMiddleware {
            var middlewareName = "Blocker"
            func intercept(context: DeeplinkContext, next: @Sendable (DeeplinkContext) async throws -> Void) async throws {
                throw DeeplinkError.blockedByMiddleware(name: "Blocker", reason: "Test")
            }
        }

        let pipeline = MiddlewarePipeline(middleware: [BlockingMiddleware()])
        let ctx = DeeplinkContext(url: URL(string: "myapp://home")!, source: .customScheme)

        do {
            try await pipeline.execute(context: ctx) { _ in XCTFail("Should not reach terminal") }
            XCTFail("Expected error")
        } catch DeeplinkError.blockedByMiddleware(let name, _) {
            XCTAssertEqual(name, "Blocker")
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }
}

// MARK: - AuthMiddlewareTests

final class AuthMiddlewareTests: XCTestCase {

    func testAllowsUnauthenticatedPublicRoute() async throws {
        let auth = AuthMiddleware(protectedRoutes: ["profile"])
        var ctx = DeeplinkContext(url: URL(string: "myapp://home")!, source: .customScheme, authState: .unauthenticated)
        let route = DeeplinkRoute(identifier: "home", rawURL: ctx.url, scheme: "myapp", host: "home")
        ctx.resolvedRoute = route

        let nextCalled = LockedValue(false)
        try await auth.intercept(context: ctx) { _ in nextCalled.set(true) }
        XCTAssertTrue(nextCalled.snapshot)
    }

    func testBlocksUnauthenticatedProtectedRoute() async {
        let auth = AuthMiddleware(protectedRoutes: ["profile"])
        var ctx = DeeplinkContext(url: URL(string: "myapp://profile/42")!, source: .customScheme, authState: .unauthenticated)
        let route = DeeplinkRoute(identifier: "profile", rawURL: ctx.url, scheme: "myapp", host: "profile")
        ctx.resolvedRoute = route

        do {
            try await auth.intercept(context: ctx) { _ in XCTFail("Should block") }
            XCTFail("Expected error")
        } catch DeeplinkError.authenticationRequired {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAllowsAuthenticatedProtectedRoute() async throws {
        let auth = AuthMiddleware(protectedRoutes: ["profile"])
        var ctx = DeeplinkContext(url: URL(string: "myapp://profile/42")!, source: .customScheme, authState: .authenticated(userID: "u1"))
        let route = DeeplinkRoute(identifier: "profile", rawURL: ctx.url, scheme: "myapp", host: "profile")
        ctx.resolvedRoute = route

        let nextCalled = LockedValue(false)
        try await auth.intercept(context: ctx) { _ in nextCalled.set(true) }
        XCTAssertTrue(nextCalled.snapshot)
    }
}
