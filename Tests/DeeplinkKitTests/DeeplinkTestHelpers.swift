// DeeplinkTestHelpers.swift
// DeeplinkKit
// Created by Kanan Abilzada.
//
// Convenience helpers for DeeplinkKit handler and pipeline unit tests.

import Foundation
import XCTest
@testable import DeeplinkKit

// MARK: - DeeplinkTestCase

/// Base XCTestCase subclass with helpers for deeplink testing.
/// Subclass this instead of XCTestCase in your handler test files.
///
/// ```swift
/// final class ProductHandlerTests: DeeplinkTestCase {
///
///     func testProductRoute() async throws {
///         let handler = ProductDeeplinkHandler()
///         let result = try await fire("myapp://product/abc", handler: handler)
///         XCTAssertEqual(result.resolvedRoute?.pathParams["productId"], "abc")
///     }
/// }
/// ```
class DeeplinkTestCase: XCTestCase {

    // MARK: - Isolated Manager

    /// A fresh, isolated DeeplinkManager for each test.
    /// Does NOT share state with `DeeplinkManager.shared`.
    private(set) var testManager: DeeplinkManager!

    override func setUp() async throws {
        try await super.setUp()
        testManager = DeeplinkManager(configuration: .init())
        let parser = StandardURLParser(schemes: ["myapp", "https"], templates: [])
        testManager.configure(parser: parser)
        testManager.markReady()
    }

    override func tearDown() async throws {
        testManager = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// Fire a URL through a specific handler directly.
    /// Parses the URL, runs `canHandle`, then calls `handle`.
    /// - Returns: The `DeeplinkContext` after handling.
    @discardableResult
    func fire(
        _ urlString: String,
        source: DeeplinkSource = .programmatic,
        authState: AuthState = .authenticated(userID: "test-user"),
        metadata: [String: String] = [:],
        handler: any DeeplinkHandling,
        parser: (any DeeplinkParsing)? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> DeeplinkContext {
        guard let url = URL(string: urlString) else {
            XCTFail("Invalid URL: \(urlString)", file: file, line: line)
            throw DeeplinkError.internal("Invalid test URL")
        }

        let activeParser: any DeeplinkParsing = parser ?? StandardURLParser(
            schemes: [url.scheme ?? "myapp", "https"],
            templates: handler.supportedPatterns
        )

        guard case .success(let route) = activeParser.parse(url: url) else {
            XCTFail("Parser could not resolve: \(urlString)", file: file, line: line)
            throw DeeplinkError.unresolvable(url)
        }

        var ctx = DeeplinkContext(url: url, source: source, authState: authState, metadata: metadata)
        ctx.resolvedRoute = route

        XCTAssertTrue(
            handler.canHandle(route: route),
            "Handler '\(handler.handlerName)' returned canHandle=false for '\(route.identifier)'",
            file: file, line: line
        )

        try await handler.handle(context: ctx)
        return ctx
    }

    /// Assert a URL parses to the expected route identifier.
    func assertParses(
        _ urlString: String,
        toIdentifier expected: String,
        using parser: any DeeplinkParsing,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let url = URL(string: urlString) else {
            XCTFail("Invalid URL: \(urlString)", file: file, line: line)
            return
        }
        switch parser.parse(url: url) {
        case .success(let route):
            XCTAssertEqual(route.identifier, expected, file: file, line: line)
        case .failure(let error):
            XCTFail("Parse failed for '\(urlString)': \(error.errorDescription)", file: file, line: line)
        }
    }

    /// Assert a URL fails to parse.
    func assertFails(
        _ urlString: String,
        using parser: any DeeplinkParsing,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let url = URL(string: urlString) else { return }
        if case .success(let route) = parser.parse(url: url) {
            XCTFail("Expected parse failure but got route '\(route.identifier)' for '\(urlString)'", file: file, line: line)
        }
    }

    /// Build a context with a pre-resolved route — shortcut for router/middleware tests.
    func makeContext(
        url: String = "myapp://test",
        routeIdentifier: String = "test",
        pathParams: [String: String] = [:],
        queryParams: [String: String] = [:],
        source: DeeplinkSource = .programmatic,
        authState: AuthState = .authenticated(userID: "test-user"),
        metadata: [String: String] = [:]
    ) -> DeeplinkContext {
        let rawURL = URL(string: url) ?? URL(string: "myapp://test")!
        let route = DeeplinkRoute(
            identifier: routeIdentifier,
            pathParams: pathParams,
            queryParams: queryParams,
            rawURL: rawURL,
            scheme: rawURL.scheme ?? "myapp",
            host: rawURL.host ?? routeIdentifier
        )
        var ctx = DeeplinkContext(url: rawURL, source: source, authState: authState, metadata: metadata)
        ctx.resolvedRoute = route
        return ctx
    }
}

// MARK: - XCTestCase Extensions (usable without subclassing)

extension XCTestCase {

    /// Assert a `DeeplinkRoute` has the expected path parameter value.
    func XCTAssertPathParam(
        _ route: DeeplinkRoute?,
        key: String,
        equals expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let route = route else {
            XCTFail("Route is nil", file: file, line: line)
            return
        }
        XCTAssertEqual(route.pathParams[key], expected, "pathParam[\(key)]", file: file, line: line)
    }

    /// Assert a `DeeplinkRoute` has the expected query parameter value.
    func XCTAssertQueryParam(
        _ route: DeeplinkRoute?,
        key: String,
        equals expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let route = route else {
            XCTFail("Route is nil", file: file, line: line)
            return
        }
        XCTAssertEqual(route.queryParams[key], expected, "queryParam[\(key)]", file: file, line: line)
    }

    /// Assert a `DeeplinkError` is of the given case.
    func XCTAssertDeeplinkError(
        _ error: Error?,
        is expectedCase: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let dlError = error as? DeeplinkError else {
            XCTFail("Error is not a DeeplinkError: \(String(describing: error))", file: file, line: line)
            return
        }
        XCTAssertTrue(
            dlError.errorDescription.contains(expectedCase) || "\(dlError)".contains(expectedCase),
            "Expected DeeplinkError case '\(expectedCase)' but got: \(dlError.errorDescription)",
            file: file, line: line
        )
    }
}
