// URLBuilderTests.swift
// DeeplinkKitTests
// Created by Kanan Abilzada.

import XCTest
@testable import DeeplinkKit

// MARK: - DeeplinkURLBuilder Tests

final class DeeplinkURLBuilderTests: XCTestCase {

    func testSimpleRoute() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("home")
            .build()
        XCTAssertEqual(url?.absoluteString, "myapp:///home")
    }

    func testRouteWithHost() {
        let url = DeeplinkURLBuilder(scheme: "myapp", host: "app")
            .route("home")
            .build()
        XCTAssertEqual(url?.absoluteString, "myapp://app/home")
    }

    func testPathParamSubstitution() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("product/:productId")
            .set("productId", "abc123")
            .build()
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("abc123"))
        XCTAssertFalse(url!.absoluteString.contains(":productId"))
    }

    func testMultiplePathParams() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("store/:storeId/product/:productId")
            .set("storeId", "s1")
            .set("productId", "p99")
            .build()
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("s1"))
        XCTAssertTrue(url!.absoluteString.contains("p99"))
    }

    func testQueryParams() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("product/:productId")
            .set("productId", "x1")
            .query("ref", "email")
            .query("tab", "reviews")
            .build()
        XCTAssertNotNil(url)
        let str = url!.absoluteString
        XCTAssertTrue(str.contains("ref=email"))
        XCTAssertTrue(str.contains("tab=reviews"))
    }

    func testQueryParamsDictionary() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("search")
            .queryParams(["q": "swift", "sort": "asc"])
            .build()
        XCTAssertNotNil(url)
        let str = url!.absoluteString
        XCTAssertTrue(str.contains("q=swift"))
        XCTAssertTrue(str.contains("sort=asc"))
    }

    func testFragment() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("product/:productId")
            .set("productId", "x")
            .fragment("reviews")
            .build()
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.fragment, "reviews")
    }

    func testUniversalLink() {
        let url = DeeplinkURLBuilder(scheme: "https", host: "app.example.com")
            .route("profile/:userId")
            .set("userId", "42")
            .build()
        XCTAssertNotNil(url)
        XCTAssertEqual(url!.scheme, "https")
        XCTAssertEqual(url!.host, "app.example.com")
        XCTAssertTrue(url!.path.contains("42"))
    }

    func testBuildThrowingSucceeds() throws {
        let url = try DeeplinkURLBuilder(scheme: "myapp")
            .route("home")
            .buildThrowing()
        XCTAssertNotNil(url)
    }

    func testIntegerParam() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("page/:number")
            .set("number", 42)
            .build()
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("42"))
    }

    func testValueSemantics() {
        let base = DeeplinkURLBuilder(scheme: "myapp").route("product/:id")
        let a = base.set("id", "aaa")
        let b = base.set("id", "bbb")
        XCTAssertNotEqual(a.build()?.absoluteString, b.build()?.absoluteString)
    }

    func testPresentationPush() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("product/:productId")
            .set("productId", "123")
            .presentation(.push)
            .build()

        XCTAssertEqual(DeeplinkOpenOptions(url: url!).presentationStyle, .push)
    }

    func testPresentationPresent() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("product/:productId")
            .set("productId", "123")
            .presentation(.present)
            .build()

        XCTAssertEqual(DeeplinkOpenOptions(url: url!).presentationStyle, .present)
        XCTAssertFalse(url!.absoluteString.contains("dk_animated"))
    }

    func testPresentationFullScreen() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("product/:productId")
            .set("productId", "123")
            .presentation(.fullScreen)
            .build()

        XCTAssertEqual(DeeplinkOpenOptions(url: url!).presentationStyle, .fullScreen)
    }

    func testPresentationSetRoot() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("home")
            .presentation(.setRoot)
            .build()

        XCTAssertEqual(DeeplinkOpenOptions(url: url!).presentationStyle, .setRoot)
    }

    func testPresentationSelectTab() {
        let url = DeeplinkURLBuilder(scheme: "myapp")
            .route("profile/:userId")
            .set("userId", "42")
            .presentation(.selectTab(2), animated: false)
            .build()

        let options = DeeplinkOpenOptions(url: url!)
        XCTAssertEqual(options.presentationStyle, .selectTab(2))
        XCTAssertFalse(options.animated)
    }
}

// MARK: - RouteRegistry Tests

final class RouteRegistryTests: XCTestCase {

    func testBuilder() {
        let registry = RouteRegistry("product/:productId")
        let url = registry.builder(scheme: "myapp").set("productId", "xyz").build()
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("xyz"))
    }

    func testStaticExtension() {
        // Demonstrates the pattern — define in your app:
        let template = RouteRegistry("home")
        let url = template.builder(scheme: "myapp").build()
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("home"))
    }
}

// MARK: - DeeplinkTestHelpers Tests (self-verifying)

final class DeeplinkTestHelpersTests: DeeplinkTestCase {

    func testMakeContext() {
        let ctx = makeContext(
            url: "myapp://product/123",
            routeIdentifier: "product",
            pathParams: ["productId": "123"],
            queryParams: ["ref": "test"]
        )
        XCTAssertEqual(ctx.resolvedRoute?.identifier, "product")
        XCTAssertEqual(ctx.resolvedRoute?.pathParams["productId"], "123")
        XCTAssertEqual(ctx.resolvedRoute?.queryParams["ref"], "test")
    }

    func testAssertPathParam() {
        let ctx = makeContext(
            routeIdentifier: "product",
            pathParams: ["productId": "abc"]
        )
        XCTAssertPathParam(ctx.resolvedRoute, key: "productId", equals: "abc")
    }

    func testAssertQueryParam() {
        let ctx = makeContext(
            routeIdentifier: "search",
            queryParams: ["q": "swift"]
        )
        XCTAssertQueryParam(ctx.resolvedRoute, key: "q", equals: "swift")
    }

    func testFireClosureHandler() async throws {
        let called = LockedValue(false)
        let handler = ClosureHandler(patterns: ["home"]) { _ in called.set(true) }
        try await fire("myapp://home", handler: handler)
        XCTAssertTrue(called.snapshot)
    }

    func testFireExtractsRoute() async throws {
        let handler = ClosureHandler(patterns: ["product/:productId"]) { _ in }
        let ctx = try await fire("myapp://product/xyz?tab=info", handler: handler)
        XCTAssertPathParam(ctx.resolvedRoute, key: "productId", equals: "xyz")
        XCTAssertQueryParam(ctx.resolvedRoute, key: "tab", equals: "info")
    }

    func testAssertFails() {
        let parser = StandardURLParser(schemes: ["myapp"], templates: ["home"])
        assertFails("ftp://something", using: parser)
    }

    func testAssertParses() {
        let parser = StandardURLParser(schemes: ["myapp"], templates: ["home"])
        assertParses("myapp://home", toIdentifier: "home", using: parser)
    }
}
