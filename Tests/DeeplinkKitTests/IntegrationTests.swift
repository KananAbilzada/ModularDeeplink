// IntegrationTests.swift
// DeeplinkKitTests
//
// End-to-end pipeline tests and coordinator recording tests.

import XCTest
@testable import DeeplinkKit

// MARK: - End-to-End Pipeline Tests

final class PipelineIntegrationTests: XCTestCase {

    var manager: DeeplinkManager!
    var parser: StandardURLParser!

    override func setUp() async throws {
        parser = StandardURLParser(
            schemes: ["myapp", "https"],
            templates: [
                "product/:productId",
                "profile/:userId",
                "home",
                "settings/:section"
            ]
        )
        manager = DeeplinkManager(configuration: .init())
        manager.configure(parser: parser)
    }

    func testFullPipelineSuccess() async throws {
        let expectation = expectation(description: "handler called")

        let handler = ClosureHandler(patterns: ["product/:productId"]) { context in
            XCTAssertEqual(context.resolvedRoute?.pathParams["productId"], "abc123")
            XCTAssertEqual(context.resolvedRoute?.queryParams["ref"], "email")
            expectation.fulfill()
        }
        manager.register(handler: handler)
        manager.markReady()

        manager.process(url: URL(string: "myapp://product/abc123?ref=email")!, source: .customScheme)

        await fulfillment(of: [expectation], timeout: 3)
    }

    func testUniversalLinkPipeline() async throws {
        let expectation = expectation(description: "universal link handled")

        let handler = ClosureHandler(patterns: ["profile/:userId"]) { context in
            XCTAssertEqual(context.source.description, "universalLink")
            XCTAssertEqual(context.resolvedRoute?.pathParams["userId"], "42")
            expectation.fulfill()
        }
        manager.register(handler: handler)
        manager.markReady()

        manager.process(url: URL(string: "https://app.example.com/profile/42")!, source: .universalLink)

        await fulfillment(of: [expectation], timeout: 3)
    }

    func testColdStartQueue() async throws {
        let expectation = expectation(description: "queued link handled after ready")

        let handler = ClosureHandler(patterns: ["home"]) { _ in
            expectation.fulfill()
        }
        manager.register(handler: handler)

        // Fire BEFORE markReady
        manager.process(url: URL(string: "myapp://home")!, source: .customScheme)

        // Short delay — ensure it hasn't fired yet
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Now mark ready — should drain queue
        manager.markReady()

        await fulfillment(of: [expectation], timeout: 3)
    }

    func testErrorCallbackOnNoHandler() async throws {
        let expectation = expectation(description: "error callback")

        manager.markReady()
        manager.onError = { _, error in
            if case DeeplinkError.noHandlerFound = error {
                expectation.fulfill()
            }
        }

        manager.process(url: URL(string: "myapp://unregistered/route")!, source: .customScheme)
        await fulfillment(of: [expectation], timeout: 3)
    }

    func testMiddlewareRunsInOrder() async throws {
        let expectation = expectation(description: "all middleware ran")
        let log = LockedArray<String>()

        struct TagMiddleware: DeeplinkMiddleware {
            let tag: String
            let logRef: @Sendable (String) -> Void
            var middlewareName: String { tag }
            func intercept(context: DeeplinkContext, next: @Sendable (DeeplinkContext) async throws -> Void) async throws {
                logRef(tag)
                try await next(context)
            }
        }

        manager.setMiddleware([
            TagMiddleware(tag: "first") { log.append($0) },
            TagMiddleware(tag: "second") { log.append($0) },
            TagMiddleware(tag: "third") { log.append($0) }
        ])

        let handler = ClosureHandler(patterns: ["home"]) { _ in
            XCTAssertEqual(log.snapshot, ["first", "second", "third"])
            expectation.fulfill()
        }
        manager.register(handler: handler)
        manager.markReady()

        manager.process(url: URL(string: "myapp://home")!)
        await fulfillment(of: [expectation], timeout: 3)
    }

    func testModuleOwnedRouteCanHandleWithoutCentralTemplate() async throws {
        let expectation = expectation(description: "module-owned route handled")
        let localManager = DeeplinkManager(configuration: .init())
        localManager.configure(parser: StandardURLParser(schemes: ["myapp"], templates: []))

        let handler = ClosureHandler(patterns: ["orders/:orderId"]) { context in
            XCTAssertEqual(context.resolvedRoute?.matchedPattern, "orders/:orderId")
            XCTAssertEqual(context.resolvedRoute?.pathParams["orderId"], "42")
            expectation.fulfill()
        }
        localManager.register(
            moduleID: "orders",
            routes: [
                DeeplinkRouteDefinition(moduleID: "orders", pattern: "orders/:orderId", handler: handler)
            ]
        )
        localManager.markReady()

        localManager.process(url: URL(string: "myapp://orders/42")!, source: .customScheme)
        await fulfillment(of: [expectation], timeout: 3)
    }

    func testAmbiguousModuleRouteIsIgnored() async throws {
        let localManager = DeeplinkManager(configuration: .init())
        localManager.configure(parser: StandardURLParser(schemes: ["myapp"], templates: []))

        let first = ClosureHandler(patterns: ["profile/:userId"]) { _ in }
        let second = ClosureHandler(patterns: ["profile/:id"]) { _ in }

        localManager.register(
            moduleID: "profile",
            routes: [
                DeeplinkRouteDefinition(moduleID: "profile", pattern: "profile/:userId", handler: first)
            ]
        )
        localManager.register(
            moduleID: "settings",
            routes: [
                DeeplinkRouteDefinition(moduleID: "settings", pattern: "profile/:id", handler: second)
            ]
        )

        XCTAssertEqual(localManager.registeredPatterns(moduleID: "profile"), ["profile/:userId"])
        XCTAssertTrue(localManager.registeredPatterns(moduleID: "settings").isEmpty)
    }

    func testProcessParsesPresentationOptionsFromURL() async throws {
        let expectation = expectation(description: "presentation options parsed")

        let handler = ClosureHandler(patterns: ["profile/:userId"]) { context in
            XCTAssertEqual(context.options.presentationStyle, .present)
            XCTAssertFalse(context.options.animated)
            XCTAssertEqual(context.resolvedRoute?.queryParams["dk_presentation"], "present")
            expectation.fulfill()
        }
        manager.register(handler: handler)
        manager.markReady()

        manager.process(url: URL(string: "myapp://profile/42?dk_presentation=present&dk_animated=false")!)
        await fulfillment(of: [expectation], timeout: 3)
    }

    func testProgrammaticOpenPassesExplicitOptionsIntoHandler() async throws {
        let expectation = expectation(description: "programmatic open handled")
        let localManager = DeeplinkManager(configuration: .init())
        localManager.configure(parser: StandardURLParser(schemes: ["myapp"], templates: []))

        let handler = ClosureHandler(patterns: ["profile/:userId"]) { context in
            XCTAssertEqual(context.resolvedRoute?.pathParams["userId"], "42")
            XCTAssertEqual(context.resolvedRoute?.queryParams["ref"], "store")
            XCTAssertEqual(context.options.presentationStyle, .selectTab(3))
            XCTAssertFalse(context.options.animated)
            expectation.fulfill()
        }
        localManager.register(handler: handler)
        localManager.markReady()

        let accepted = localManager.open(
            RouteRegistry("profile/:userId"),
            parameters: ["userId": "42"],
            query: ["ref": "store"],
            options: .init(presentationStyle: .selectTab(3), animated: false),
            scheme: "myapp"
        )

        XCTAssertTrue(accepted)
        await fulfillment(of: [expectation], timeout: 3)
    }
}

// MARK: - RecordingNavigationCoordinator Tests

final class RecordingCoordinatorTests: XCTestCase {

    func testRecordsNavigation() async {
        let coordinator = RecordingNavigationCoordinator()
        let route = DeeplinkRoute(
            identifier: "product",
            pathParams: ["productId": "x"],
            rawURL: URL(string: "myapp://product/x")!,
            scheme: "myapp",
            host: "product"
        )

        await coordinator.push(route: route)
        await coordinator.present(route: route)
        await coordinator.selectTab(index: 2)
        await coordinator.popToRoot()

        XCTAssertEqual(coordinator.pushedRoutes.count, 1)
        XCTAssertEqual(coordinator.presentedRoutes.count, 1)
        XCTAssertEqual(coordinator.selectedTabs, [2])
        XCTAssertEqual(coordinator.popToRootCalls, 1)
    }

    func testReset() async {
        let coordinator = RecordingNavigationCoordinator()
        let route = DeeplinkRoute(identifier: "home", rawURL: URL(string: "myapp://home")!, scheme: "myapp", host: "home")
        await coordinator.push(route: route)
        coordinator.reset()
        XCTAssertTrue(coordinator.pushedRoutes.isEmpty)
    }
}

// MARK: - DeeplinkQueue Tests

final class DeeplinkQueueTests: XCTestCase {

    func testEnqueueAndDrain() {
        let queue = DeeplinkQueue()
        let ctx = DeeplinkContext(url: URL(string: "myapp://home")!, source: .customScheme)
        queue.enqueue(ctx)
        queue.enqueue(ctx)

        XCTAssertEqual(queue.count, 2)
        let drained = queue.drain()
        XCTAssertEqual(drained.count, 2)
        XCTAssertTrue(queue.isEmpty)
    }

    func testCapacityDrop() {
        var config = DeeplinkQueue.Configuration()
        config.capacity = 3
        let queue = DeeplinkQueue(configuration: config)

        for i in 0..<5 {
            let url = URL(string: "myapp://item/\(i)")!
            queue.enqueue(DeeplinkContext(url: url, source: .customScheme))
        }

        XCTAssertEqual(queue.count, 3)
        let drained = queue.drain()
        // Should have dropped the first 2, kept last 3
        XCTAssertEqual(drained.last?.url.absoluteString, "myapp://item/4")
    }

    func testDrainIsDestructive() {
        let queue = DeeplinkQueue()
        let ctx = DeeplinkContext(url: URL(string: "myapp://home")!, source: .customScheme)
        queue.enqueue(ctx)
        _ = queue.drain()
        XCTAssertTrue(queue.isEmpty)
    }
}

// MARK: - BuiltInHandlers Tests

final class BuiltInHandlerTests: XCTestCase {

    func testNoOpHandlerNeverThrows() async throws {
        let handler = NoOpHandler(patterns: ["*"])
        let ctx = DeeplinkContext(url: URL(string: "myapp://anything")!, source: .customScheme)
        try await handler.handle(context: ctx)
    }

    func testClosureHandlerCanThrow() async {
        let handler = ClosureHandler(patterns: ["bad"]) { _ in
            throw DeeplinkError.internal("test error")
        }
        let ctx = DeeplinkContext(url: URL(string: "myapp://bad")!, source: .customScheme)
        do {
            try await handler.handle(context: ctx)
            XCTFail("Expected throw")
        } catch DeeplinkError.internal(let msg) {
            XCTAssertEqual(msg, "test error")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testClosureHandlerPatternCheck() {
        let handler = ClosureHandler(patterns: ["product/:id", "home"]) { _ in }
        let productRoute = DeeplinkRoute(identifier: "product", pathParams: ["id": "1"], rawURL: URL(string: "myapp://product/1")!, scheme: "myapp", host: "product")
        let homeRoute = DeeplinkRoute(identifier: "home", rawURL: URL(string: "myapp://home")!, scheme: "myapp", host: "home")
        let otherRoute = DeeplinkRoute(identifier: "chat", rawURL: URL(string: "myapp://chat")!, scheme: "myapp", host: "chat")

        XCTAssertTrue(handler.canHandle(route: productRoute))
        XCTAssertTrue(handler.canHandle(route: homeRoute))
        XCTAssertFalse(handler.canHandle(route: otherRoute))
    }
}

// MARK: - DeeplinkError Tests

final class DeeplinkErrorTests: XCTestCase {

    func testErrorDescriptions() {
        let url = URL(string: "myapp://x")!
        let errors: [DeeplinkError] = [
            .unresolvable(url),
            .unsupportedScheme("ftp"),
            .missingParameter("productId"),
            .invalidParameter(key: "page", value: "abc"),
            .authenticationRequired(redirectURL: nil),
            .blockedByMiddleware(name: "Auth", reason: "not logged in"),
            .timeout(after: 10),
            .internal("oops")
        ]

        for error in errors {
            XCTAssertFalse(error.errorDescription.isEmpty, "Empty description for \(error)")
        }
    }
}
