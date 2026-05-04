// DeeplinkCoordinator.swift
// DeeplinkKit
//
// Navigation coordinator protocol for use inside handlers.
// Your app's navigation layer conforms to this — handlers call it
// without importing UIKit/SwiftUI directly.

import Foundation

// MARK: - NavigationCoordinating

/// Abstract navigation interface that handlers call to perform routing.
/// Your app's coordinator / router conforms to this protocol.
/// This keeps handlers free of UIKit / SwiftUI imports.
public protocol NavigationCoordinating: AnyObject, Sendable {

    /// Push a destination (identified by route) onto the current stack.
    func push(route: DeeplinkRoute, animated: Bool) async

    /// Present a destination modally.
    func present(route: DeeplinkRoute, animated: Bool) async

    /// Replace the root/tab destination.
    func setRoot(route: DeeplinkRoute, animated: Bool) async

    /// Dismiss any presented view and reset to root.
    func popToRoot(animated: Bool) async

    /// Switch to a tab by index, if applicable.
    func selectTab(index: Int) async
}

// MARK: - Default Implementations

public extension NavigationCoordinating {
    func push(route: DeeplinkRoute, animated: Bool = true) async {
        await push(route: route, animated: animated)
    }
    func present(route: DeeplinkRoute, animated: Bool = true) async {
        await present(route: route, animated: animated)
    }
    func setRoot(route: DeeplinkRoute, animated: Bool = false) async {
        await setRoot(route: route, animated: animated)
    }
    func popToRoot(animated: Bool = true) async {
        await popToRoot(animated: animated)
    }
}

// MARK: - NoOpNavigationCoordinator

/// Silent no-op coordinator. Use in unit tests or previews.
public final class NoOpNavigationCoordinator: NavigationCoordinating {
    public init() {}
    public func push(route: DeeplinkRoute, animated: Bool) async {}
    public func present(route: DeeplinkRoute, animated: Bool) async {}
    public func setRoot(route: DeeplinkRoute, animated: Bool) async {}
    public func popToRoot(animated: Bool) async {}
    public func selectTab(index: Int) async {}
}

// MARK: - RecordingNavigationCoordinator (for testing)

/// Records all navigation calls. Use in handler unit tests to assert navigation.
///
/// Usage:
/// ```swift
/// let coordinator = RecordingNavigationCoordinator()
/// var ctx = DeeplinkContext(url: url, source: .customScheme)
/// ctx.resolvedRoute = route
/// try await handler.handle(context: ctx)
/// XCTAssertEqual(coordinator.pushedRoutes.last?.identifier, "product")
/// ```
public final class RecordingNavigationCoordinator: NavigationCoordinating, @unchecked Sendable {
    public private(set) var pushedRoutes: [DeeplinkRoute] = []
    public private(set) var presentedRoutes: [DeeplinkRoute] = []
    public private(set) var rootRoutes: [DeeplinkRoute] = []
    public private(set) var popToRootCalls: Int = 0
    public private(set) var selectedTabs: [Int] = []

    public init() {}

    public func push(route: DeeplinkRoute, animated: Bool) async {
        pushedRoutes.append(route)
    }
    public func present(route: DeeplinkRoute, animated: Bool) async {
        presentedRoutes.append(route)
    }
    public func setRoot(route: DeeplinkRoute, animated: Bool) async {
        rootRoutes.append(route)
    }
    public func popToRoot(animated: Bool) async {
        popToRootCalls += 1
    }
    public func selectTab(index: Int) async {
        selectedTabs.append(index)
    }

    public func reset() {
        pushedRoutes.removeAll()
        presentedRoutes.removeAll()
        rootRoutes.removeAll()
        popToRootCalls = 0
        selectedTabs.removeAll()
    }
}
